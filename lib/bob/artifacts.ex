defmodule Bob.Artifacts do
  import Ecto.Query

  alias Bob.Repo
  alias Bob.Artifacts.{Artifact, BaseImageTag, DockerTag, DockerTagSearch, DockerTagStaging}

  @builds_txt_lock 4_771_002

  # Each staging row binds six parameters; Postgres caps a statement at 65535,
  # so a page is inserted in chunks well under that ceiling.
  @staging_chunk 5000

  # Reconcile/backfill rewrites a repo's entire tag set through
  # docker_tags_staging (up to ~1M rows for hexpm/elixir). Queries over that full
  # set can run longer than Postgrex's 15s default, so each passes this timeout
  # explicitly — a transaction's :timeout does not propagate to the queries it
  # wraps.
  @long_query_timeout 5 * 60 * 1000

  def add(attrs) do
    upsert(attrs)
    generate_builds_txt(attrs.arch, attrs.os)
    Bob.Fastly.purge_builds(purge_keys(attrs.arch, attrs.os, attrs.name))
    :ok
  end

  def add_docker_tag(repo, tag, archs, built_at \\ DateTime.utc_now()) do
    now = NaiveDateTime.utc_now()
    built_at = dump_utc_datetime(built_at)
    search = DockerTagSearch.metadata(repo, tag)

    Repo.query!(
      """
      INSERT INTO docker_tags (repo, tag, archs, search, built_at, inserted_at, updated_at)
      VALUES ($1, $2, $3, $4, $5, $6, $6)
      ON CONFLICT (repo, tag)
      DO UPDATE SET
        archs = (
          SELECT array_agg(DISTINCT a ORDER BY a)
          FROM unnest(docker_tags.archs || EXCLUDED.archs) AS a
        ),
        search = EXCLUDED.search,
        built_at = EXCLUDED.built_at,
        updated_at = EXCLUDED.updated_at
      """,
      [repo, tag, archs, search, built_at, now]
    )

    :ok
  end

  @doc """
  Inserts a page of `{tag, archs, built_at}` tuples into the staging table under `token`.

  Reconcile streams Docker Hub a page at a time into staging so the full tag
  list (up to ~1M for hexpm/elixir) is never held in memory and no connection is
  held across the multi-minute fetch. The `token` isolates this run's rows from
  any concurrent reconcile of the same repo; `swap_docker_tags/2` then applies
  them. Cross-page duplicates are tolerated and de-duplicated at swap time.
  """
  def stage_docker_tags(_token, _repo, []), do: :ok

  def stage_docker_tags(token, repo, tag_archs_built_at) do
    now = NaiveDateTime.utc_now()

    tag_archs_built_at
    |> Enum.map(fn {tag, archs, built_at} ->
      %{
        token: token,
        repo: repo,
        tag: tag,
        archs: archs,
        search: DockerTagSearch.metadata(repo, tag),
        built_at: built_at,
        inserted_at: now
      }
    end)
    |> Enum.chunk_every(@staging_chunk)
    |> Enum.each(&Repo.insert_all(DockerTagStaging, &1))

    :ok
  end

  @doc """
  Applies the tags staged under `token` for `repo` to `docker_tags`, in one
  transaction: upsert every staged tag, prune any `docker_tags` row whose tag is
  no longer staged, then drop the staging rows. `DISTINCT ON` collapses any
  duplicate tags Docker Hub returned across pages.

  Only call this once the full fetch succeeded — a partial fetch would prune
  tags that were merely not yet fetched.
  """
  def swap_docker_tags(token, repo) do
    now = NaiveDateTime.utc_now()

    Repo.transaction(
      fn ->
        Repo.query!(
          """
          INSERT INTO docker_tags (repo, tag, archs, search, built_at, inserted_at, updated_at)
          SELECT DISTINCT ON (repo, tag) repo, tag, archs, search, built_at, $3, $3
          FROM docker_tags_staging
          WHERE token = $1 AND repo = $2
          ORDER BY repo, tag, built_at DESC
          ON CONFLICT (repo, tag)
          DO UPDATE SET
            archs = EXCLUDED.archs,
            search = EXCLUDED.search,
            built_at = EXCLUDED.built_at,
            updated_at = EXCLUDED.updated_at
          WHERE docker_tags.archs IS DISTINCT FROM EXCLUDED.archs
             OR docker_tags.search IS DISTINCT FROM EXCLUDED.search
             OR docker_tags.built_at IS DISTINCT FROM EXCLUDED.built_at
          """,
          [token, repo, now],
          timeout: @long_query_timeout
        )

        Repo.query!(
          """
          DELETE FROM docker_tags d
          WHERE d.repo = $2
            AND NOT EXISTS (
              SELECT 1 FROM docker_tags_staging s
              WHERE s.token = $1 AND s.repo = d.repo AND s.tag = d.tag
            )
          """,
          [token, repo],
          timeout: @long_query_timeout
        )

        Repo.query!(
          "DELETE FROM docker_tags_staging WHERE token = $1 AND repo = $2",
          [token, repo],
          timeout: @long_query_timeout
        )
      end,
      timeout: @long_query_timeout
    )

    :ok
  end

  @doc """
  Whether any tag is staged under `token` for `repo`. `EXISTS` stops at the
  first matching row via the `(token, repo, tag)` index, so this stays cheap even
  when a full repo (~1M rows) is staged — unlike counting every distinct tag.
  """
  def staged_any?(token, repo) do
    %{rows: [[exists?]]} =
      Repo.query!(
        "SELECT EXISTS(SELECT 1 FROM docker_tags_staging WHERE token = $1 AND repo = $2)",
        [token, repo]
      )

    exists?
  end

  @doc "Number of distinct tags staged under `token` for `repo`."
  def staged_tag_count(token, repo) do
    %{rows: [[count]]} =
      Repo.query!(
        "SELECT count(DISTINCT tag) FROM docker_tags_staging WHERE token = $1 AND repo = $2",
        [token, repo],
        timeout: @long_query_timeout
      )

    count
  end

  @doc "Distinct staged tags for `repo` whose arch list covers every arch in `archs`."
  def staged_multi_arch_tags(token, repo, archs) do
    %{rows: rows} =
      Repo.query!(
        "SELECT DISTINCT tag FROM docker_tags_staging WHERE token = $1 AND repo = $2 AND archs @> $3",
        [token, repo, archs],
        timeout: @long_query_timeout
      )

    Enum.map(rows, fn [tag] -> tag end)
  end

  @doc "Drops every staging row for `token` (used when a fetch fails partway)."
  def discard_staging(token) do
    Repo.query!("DELETE FROM docker_tags_staging WHERE token = $1", [token],
      timeout: @long_query_timeout
    )

    :ok
  end

  @doc """
  Deletes staging rows older than `older_than_seconds`, reclaiming rows orphaned
  by a process that died between staging and the swap. The age threshold must
  exceed any single sweep's duration so it never touches an in-flight run.
  """
  def prune_staging(older_than_seconds) do
    cutoff =
      NaiveDateTime.utc_now()
      |> NaiveDateTime.add(-older_than_seconds, :second)

    %{num_rows: num_rows} =
      Repo.query!("DELETE FROM docker_tags_staging WHERE inserted_at < $1", [cutoff],
        timeout: @long_query_timeout
      )

    num_rows
  end

  def search_artifacts(filters \\ %{}, limit \\ 100, offset \\ 0) do
    filters
    |> artifact_search_query()
    |> order_by([a], desc: a.built_at, desc: a.id)
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
  end

  def count_artifacts(filters \\ %{}) do
    filters
    |> artifact_search_query()
    |> Repo.aggregate(:count, :id)
  end

  def search_docker_tags(filters \\ %{}, limit \\ 100, offset \\ 0) do
    filters
    |> docker_tag_search_query()
    |> order_by([d], desc: d.built_at, desc: d.id)
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
  end

  def count_docker_tags(filters \\ %{}) do
    filters
    |> docker_tag_search_query()
    |> Repo.aggregate(:count, :id)
  end

  def distinct_kinds(), do: distinct_values(Artifact, :kind)
  def distinct_arches(), do: distinct_values(Artifact, :arch)
  def distinct_oses(), do: distinct_values(Artifact, :os)
  def distinct_repos(), do: distinct_values(DockerTag, :repo)

  def docker_tag_filter_options() do
    %{
      repos: DockerTagSearch.repos(),
      arches: DockerTagSearch.arches(),
      oses: DockerTagSearch.oses()
    }
  end

  def distinct_docker_arches(), do: DockerTagSearch.arches()

  def distinct_docker_oses(), do: DockerTagSearch.oses()

  defp distinct_values(schema, field) do
    Repo.all(
      from(s in schema, distinct: true, select: field(s, ^field), order_by: field(s, ^field))
    )
  end

  defp artifact_search_query(filters) do
    query = blank_to_nil(Map.get(filters, :query))

    Artifact
    |> text_filter(query, [:name, :ref])
    |> eq_filter(:kind, Map.get(filters, :kind))
    |> eq_filter(:arch, Map.get(filters, :arch))
    |> eq_filter(:os, Map.get(filters, :os))
  end

  defp docker_tag_search_query(filters) do
    DockerTag
    |> prefix_filter(:repo, Map.get(filters, :repo))
    |> prefix_filter(:tag, Map.get(filters, :tag))
    |> arch_prefix_filter(Map.get(filters, :arch))
    |> search_metadata_prefix_filter(:elixir_version, Map.get(filters, :elixir_version))
    |> search_metadata_prefix_filter(:erlang_version, Map.get(filters, :erlang_version))
    |> search_metadata_prefix_filter(:os, Map.get(filters, :os))
    |> search_metadata_prefix_filter(:os_version, Map.get(filters, :os_version))
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp dump_utc_datetime(%DateTime{} = datetime) do
    datetime
    |> DateTime.to_naive()
    |> NaiveDateTime.truncate(:microsecond)
  end

  defp dump_utc_datetime(%NaiveDateTime{} = datetime) do
    NaiveDateTime.truncate(datetime, :microsecond)
  end

  defp eq_filter(query, _field, nil), do: query
  defp eq_filter(query, _field, ""), do: query
  defp eq_filter(query, field, value), do: from(s in query, where: field(s, ^field) == ^value)

  defp prefix_filter(query, _field, nil), do: query
  defp prefix_filter(query, _field, ""), do: query

  defp prefix_filter(query, field, value) do
    pattern = prefix_pattern(value)
    from(s in query, where: fragment("? LIKE ? ESCAPE '\\'", field(s, ^field), ^pattern))
  end

  defp arch_prefix_filter(query, nil), do: query
  defp arch_prefix_filter(query, ""), do: query

  defp arch_prefix_filter(query, value) when value in ["amd64", "arm64"] do
    from(d in query, where: fragment("? @> ?", d.archs, ^[value]))
  end

  defp arch_prefix_filter(query, value) do
    pattern = prefix_pattern(value)

    from(d in query,
      where:
        fragment(
          "EXISTS (SELECT 1 FROM unnest(?) AS arch(value) WHERE value LIKE ? ESCAPE '\\')",
          d.archs,
          ^pattern
        )
    )
  end

  defp search_metadata_prefix_filter(query, _field, nil), do: query
  defp search_metadata_prefix_filter(query, _field, ""), do: query

  defp search_metadata_prefix_filter(query, :elixir_version, value) do
    pattern = prefix_pattern(value)

    from(d in query,
      where: fragment("?->>'elixir_version' LIKE ? ESCAPE '\\'", d.search, ^pattern)
    )
  end

  defp search_metadata_prefix_filter(query, :erlang_version, value) do
    pattern = prefix_pattern(value)

    from(d in query,
      where: fragment("?->>'erlang_version' LIKE ? ESCAPE '\\'", d.search, ^pattern)
    )
  end

  defp search_metadata_prefix_filter(query, :os, value) do
    pattern = prefix_pattern(value)
    from(d in query, where: fragment("?->>'os' LIKE ? ESCAPE '\\'", d.search, ^pattern))
  end

  defp search_metadata_prefix_filter(query, :os_version, value) do
    pattern = prefix_pattern(value)

    from(d in query,
      where: fragment("?->>'os_version' LIKE ? ESCAPE '\\'", d.search, ^pattern)
    )
  end

  defp prefix_pattern(value), do: escape_like(value) <> "%"

  defp text_filter(query, nil, _fields), do: query

  defp text_filter(query, text, [first_field | rest_fields]) do
    pattern = "%" <> escape_like(text) <> "%"

    conditions =
      Enum.reduce(rest_fields, dynamic([s], ilike(field(s, ^first_field), ^pattern)), fn field,
                                                                                         acc ->
        dynamic([s], ^acc or ilike(field(s, ^field), ^pattern))
      end)

    from(s in query, where: ^conditions)
  end

  defp escape_like(string) do
    String.replace(string, ~r/([\\%_])/, "\\\\\\1")
  end

  def docker_tags(repo) do
    Repo.all(
      from(d in DockerTag,
        where: d.repo == ^repo,
        select: {d.tag, d.archs}
      )
    )
  end

  def base_image_tags(repo) do
    Repo.all(
      from(b in BaseImageTag,
        where: b.repo == ^repo,
        select: b.tag
      )
    )
  end

  def replace_base_image_tags(repo, tags) do
    now = DateTime.utc_now()

    rows =
      tags |> Enum.uniq() |> Enum.map(&%{repo: repo, tag: &1, inserted_at: now, updated_at: now})

    Repo.transaction(fn ->
      Repo.delete_all(from(b in BaseImageTag, where: b.repo == ^repo))
      Repo.insert_all(BaseImageTag, rows)
    end)

    :ok
  end

  def upsert(attrs) do
    %Artifact{}
    |> Artifact.changeset(attrs)
    |> Repo.insert!(
      on_conflict: {:replace, [:ref, :sha256, :built_at, :updated_at]},
      conflict_target: [:kind, :arch, :os, :name]
    )
  end

  @doc """
  Bulk-upserts artifact rows in a single statement, replacing
  `ref`/`sha256`/`built_at` on a conflicting `(kind, arch, os, name)`. The
  backfill imports each builds.txt with one insert rather than a query per line.
  Rows must already carry dumped values (e.g. `built_at` as a `DateTime`).
  """
  def import_artifacts([]), do: :ok

  def import_artifacts(rows) do
    now = DateTime.utc_now()

    rows =
      rows
      |> Enum.uniq_by(&{&1.kind, &1.arch, &1.os, &1.name})
      |> Enum.map(&Map.merge(&1, %{inserted_at: now, updated_at: now}))

    Repo.insert_all(Artifact, rows,
      on_conflict: {:replace, [:ref, :sha256, :built_at, :updated_at]},
      conflict_target: [:kind, :arch, :os, :name]
    )

    :ok
  end

  def built_otp_refs(arch, os) do
    Repo.all(
      from(a in Artifact,
        where: a.kind == "otp" and a.arch == ^arch and a.os == ^os,
        select: {a.name, a.ref}
      )
    )
    |> Map.new()
  end

  def builds_txt(arch, os) do
    Repo.all(
      from(a in Artifact,
        where: a.kind == "otp" and a.arch == ^arch and a.os == ^os,
        order_by: fragment("? COLLATE \"C\"", a.name),
        select: {a.name, a.ref, a.built_at, a.sha256}
      )
    )
    |> Enum.map_join(fn
      {name, ref, built_at, nil} ->
        "#{name} #{ref} #{format_date(built_at)}\n"

      {name, ref, built_at, sha256} ->
        "#{name} #{ref} #{format_date(built_at)} #{sha256}\n"
    end)
  end

  def generate_builds_txt(arch, os) do
    {:ok, path} =
      Repo.transaction(fn ->
        Repo.query!("SELECT pg_advisory_xact_lock($1, $2)", [@builds_txt_lock, lock_key(arch, os)])

        path = "builds/otp/#{arch}/#{os}/builds.txt"

        Bob.Store.put_file(path, builds_txt(arch, os),
          cache_control: "public,max-age=3600",
          meta: [
            {"surrogate-key", surrogate_keys(arch, os)},
            {"surrogate-control", "public,max-age=604800"}
          ]
        )

        path
      end)

    path
  end

  # The lock serializes concurrent regenerations of the same (arch, os) so the
  # last writer renders from the latest rows. It is a performance guard, not a
  # correctness guard: a hash collision between two (arch, os) pairs only makes
  # them serialize unnecessarily, since each render is scoped by arch/os anyway.
  defp lock_key(arch, os) do
    :erlang.phash2("#{arch}/#{os}", 2_147_483_647)
  end

  defp surrogate_keys(arch, os) do
    "builds builds/otp builds/otp/#{arch} builds/otp/#{arch}/#{os} builds/otp/#{arch}/#{os}/txt"
  end

  defp purge_keys(arch, os, name) do
    "builds/otp/#{arch}/#{os}/txt builds/otp/#{arch}/#{os}/#{name}"
  end

  defp format_date(built_at) do
    Calendar.strftime(built_at, "%Y-%m-%dT%H:%M:%SZ")
  end
end

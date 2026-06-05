defmodule Bob.Artifacts do
  import Ecto.Query

  alias Bob.Repo
  alias Bob.Artifacts.Artifact

  @builds_txt_lock 4_771_002

  def add(attrs) do
    upsert(attrs)
    generate_builds_txt(attrs.arch, attrs.os)
    Bob.Fastly.purge_builds(purge_keys(attrs.arch, attrs.os, attrs.name))
    :ok
  end

  def upsert(attrs) do
    %Artifact{}
    |> Artifact.changeset(attrs)
    |> Repo.insert!(
      on_conflict: {:replace, [:ref, :sha256, :built_at]},
      conflict_target: [:kind, :arch, :os, :name]
    )
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
    |> Enum.map_join(fn {name, ref, built_at, sha256} ->
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

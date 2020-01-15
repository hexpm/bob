defmodule Bob.Job.BuildDockerChecker do
  @erlang_build_regex ~r"^OTP-(\d+(?:\.\d+)?(?:\.\d+))?$"
  @erlang_tag_regex ~r"^((\d+)(?:\.\d+)?(?:\.\d+)?)-alpine-.+$"
  @elixir_build_regex ~r"^v(\d+\.\d+\.\d+)-otp-(\d+)$"
  @elixir_tag_regex ~r"^(.+)-erlang-(.+)-alpine-.+$"

  def run([]) do
    erlang()
    elixir()
  end

  defp erlang() do
    builds = Map.keys(Bob.Repo.fetch_built_refs("builds/otp/alpine-3.10"))
    tags = Bob.DockerHub.fetch_repo_tags("hexpm/erlang")

    Enum.each(diff_erlang_tags(builds, tags), fn ref ->
      Bob.Queue.run(Bob.Job.BuildDockerErlang, [ref])
    end)
  end

  defp diff_erlang_tags(builds, tags) do
    builds = builds |> Enum.map(&parse_erlang_build/1) |> Enum.filter(& &1)

    tags =
      Enum.map(tags, fn tag ->
        {erlang, _major} = parse_erlang_tag(tag)
        erlang
      end)

    builds -- tags
  end

  defp parse_erlang_build(build) do
    case Regex.run(@erlang_build_regex, build, capture: :all_but_first) do
      [version] -> version
      nil -> nil
    end
  end

  defp elixir() do
    erlang_tags = Bob.DockerHub.fetch_repo_tags("hexpm/erlang")
    elixir_builds = Map.keys(Bob.Repo.fetch_built_refs("builds/elixir"))
    tags = Bob.DockerHub.fetch_repo_tags("hexpm/elixir")

    builds =
      for elixir_build <- elixir_builds,
          build_elixir?(elixir_build),
          {elixir, elixir_erlang_major} = parse_elixir_build(elixir_build),
          erlang_tag <- erlang_tags,
          {erlang, erlang_major} = parse_erlang_tag(erlang_tag),
          elixir_erlang_major == erlang_major,
          do: {elixir, erlang, erlang_major}

    Enum.each(diff_elixir_tags(builds, tags), fn {elixir, erlang, erlang_major} ->
      Bob.Queue.run(Bob.Job.BuildDockerElixir, [elixir, erlang, erlang_major])
    end)
  end

  defp build_elixir?(build) do
    Regex.match?(@elixir_build_regex, build)
  end

  defp parse_elixir_build(build) do
    [elixir, erlang_major] = Regex.run(@elixir_build_regex, build, capture: :all_but_first)
    {elixir, erlang_major}
  end

  defp parse_erlang_tag(tag) do
    [erlang, major] = Regex.run(@erlang_tag_regex, tag, capture: :all_but_first)
    {erlang, major}
  end

  defp diff_elixir_tags(builds, tags) do
    tags =
      MapSet.new(tags, fn tag ->
        [elixir, erlang] = Regex.run(@elixir_tag_regex, tag, capture: :all_but_first)
        {elixir, erlang}
      end)

    Enum.reject(builds, fn {elixir, erlang, _erlang_major} ->
      {elixir, erlang} in tags
    end)
  end

  def equal?(_, _), do: true

  def similar?(_, _), do: true
end

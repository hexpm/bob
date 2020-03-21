defmodule Bob do
  def log_error(kind, error, stacktrace) do
    formatted_banner = Exception.format_banner(kind, error, stacktrace)
    formatted_stacktrace = Exception.format_stacktrace(stacktrace)
    exception = Exception.normalize(kind, error, stacktrace)

    IO.puts(:stderr, formatted_banner <> "\n" <> formatted_stacktrace)
    Rollbax.report(kind, exception, stacktrace)
  end

  def build_elixir(ref_name) do
    ref = Bob.GitHub.fetch_repo_refs("elixir-lang/elixir") |> Map.new() |> Map.fetch!(ref_name)
    Bob.Queue.add(Bob.Job.BuildElixir, [ref_name, ref])
  end

  def build_otp(ref_name, linux \\ "ubuntu-14.04") do
    ref = Bob.GitHub.fetch_repo_refs("erlang/otp") |> Map.new() |> Map.fetch!(ref_name)
    Bob.Queue.add(Bob.Job.BuildOTP, [ref_name, ref, linux])
  end

  def build_elixir_guides() do
    Bob.Queue.add(Bob.Job.BuildElixirGuides, ["master"])
  end

  def build_hex_docs(ref_name) do
    Bob.Queue.add(Bob.Job.BuildHexDocs, [ref_name])
  end

  def build_docker_erlang(erlang, os, os_version, arch) do
    Bob.Queue.add(Bob.Job.BuildDockerErlang, [arch, erlang, os, os_version])
  end

  def build_docker_elixir(elixir, erlang, os, os_version, arch) do
    Bob.Queue.add(Bob.Job.BuildDockerElixir, [arch, elixir, erlang, os, os_version])
  end

  def tmp_dir() do
    Application.get_env(:bob, :tmp_dir)
  end

  def persist_dir() do
    Application.get_env(:bob, :persist_dir)
  end
end

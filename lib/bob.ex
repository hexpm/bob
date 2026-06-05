defmodule Bob do
  def log_error(exception, stacktrace) do
    formatted_banner = Exception.format_banner(:error, exception, stacktrace)
    formatted_stacktrace = Exception.format_stacktrace(stacktrace)

    IO.puts(:stderr, formatted_banner <> "\n" <> formatted_stacktrace)
    Sentry.capture_exception(exception, stacktrace: stacktrace)
  end

  def build_otp(ref_name, linux) do
    ref = Bob.GitHub.fetch_repo_refs("erlang/otp") |> Map.new() |> Map.fetch!(ref_name)
    Bob.Queue.add(Bob.Job.BuildOTP, [ref_name, ref, linux])
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

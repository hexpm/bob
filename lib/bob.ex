defmodule Bob do
  use Application

  def start(_type, _args) do
    opts = [port: port(), compress: true]

    File.mkdir_p!(tmp_dir())
    Plug.Adapters.Cowboy.http(Bob.Router, [], opts)
    Bob.Supervisor.start_link()
  end

  def log_error(kind, error, stacktrace) do
    formatted_banner = Exception.format_banner(kind, error, stacktrace)
    formatted_stacktrace = Exception.format_stacktrace(stacktrace)
    exception = Exception.normalize(kind, error, stacktrace)

    IO.puts(:stderr, formatted_banner <> "\n" <> formatted_stacktrace)
    Rollbax.report(kind, exception, stacktrace)
  end

  defp port() do
    if port = System.get_env("BOB_PORT") do
      String.to_integer(port)
    else
      4003
    end
  end

  def build_elixir(ref) do
    Bob.Queue.run(Bob.Job.BuildElixir, ["push", ref])
  end

  def build_otp(ref_name, linux \\ "ubuntu-14.04") do
    ref = Bob.GitHub.fetch_repo_refs("erlang/otp") |> Map.new() |> Map.fetch!(ref_name)
    Bob.Queue.run(Bob.Job.BuildOTP, [ref_name, ref, linux])
  end

  def build_elixir_guides() do
    Bob.Queue.run(Bob.Job.BuildElixirGuides, ["push", "master"])
  end

  def build_hex_docs(ref) do
    Bob.Queue.run(Bob.Job.BuildHexDocs, ["push", ref])
  end

  def tmp_dir() do
    Application.get_env(:bob, :tmp_dir)
  end

  def persist_dir() do
    Application.get_env(:bob, :persist_dir)
  end
end

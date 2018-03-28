defmodule Bob do
  use Application

  # TOOD: Better duplicate check for OTP builds since we include the sha with the branch name
  # in the arguments which means two quick commits to the same branch will trigger two builds
  # instead of only one

  def start(_type, _args) do
    opts = [port: port(), compress: true]

    File.mkdir_p!("tmp")
    Plug.Adapters.Cowboy.http(Bob.Router, [], opts)
    Bob.Supervisor.start_link()
  end

  def log_error(kind, error, stacktrace) do
    banner = Exception.format_banner(kind, error, stacktrace)
    stacktrace = Exception.format_stacktrace(stacktrace)
    IO.puts(:stderr, banner <> "\n" <> stacktrace)
  end

  defp port() do
    if port = System.get_env("PORT") do
      String.to_integer(port)
    else
      4000
    end
  end

  def build_elixir(ref) do
    Bob.Queue.run(Bob.Job.BuildElixir, ["push", ref])
  end

  def build_otp(ref_name) do
    ref = Bob.GitHub.fetch_repo_refs("erlang/otp") |> Map.new() |> Map.fetch!(ref_name)
    Bob.Queue.run(Bob.Job.BuildOTP, [ref_name, ref])
  end

  def build_elixir_guides() do
    Bob.Queue.run(Bob.Job.BuildElixirGuides, ["push", "master"])
  end
end

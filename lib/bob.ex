defmodule Bob do
  use Application

  def start(_type, _args) do
    opts  = [port: 4000, comress: true]

    if port = System.get_env("PORT") do
      opts = Keyword.put(opts, :port, String.to_integer(port))
    end

    File.mkdir_p!("tmp")
    Plug.Adapters.Cowboy.http(Bob.Router, [], opts)
    Bob.Supervisor.start_link
  end

  def log_error(kind, error, stacktrace) do
    IO.puts(:stderr, Exception.format_banner(kind, error, stacktrace) <> "\n" <>
                     Exception.format_stacktrace(stacktrace))
  end

  def upload_path(repo, ref) do
    [_repo, name] = :binary.split(repo, "/")
    "builds/#{name}/#{ref}.zip"
  end
end

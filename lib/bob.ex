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

  def upload_path(name, ref) do
    "builds/#{name}/#{ref}.zip"
  end

  def format_datetime({{year, month, day}, {hour, min, sec}}) do
    list = [year, month, day, hour, min, sec]
    :io_lib.format("~4..0B-~2..0B-~2..0B ~2..0B:~2..0B:~2..0B", list)
    |> IO.iodata_to_binary
  end
end

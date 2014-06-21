defmodule Bob do
  use Application

  def start(_type, _args) do
    opts = [port: Application.get_env(:bob, :port),
            compress: true]

    File.mkdir_p!("tmp")
    Plug.Adapters.Cowboy.http(Bob.Router, [], opts)
    Bob.Supervisor.start_link
  end
end

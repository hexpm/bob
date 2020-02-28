defmodule Bob.Application do
  use Application

  def start(_type, _args) do
    opts = [port: port(), compress: true]

    setup_docker()
    setup_gsutil()
    File.mkdir_p!(Bob.tmp_dir())
    Plug.Adapters.Cowboy.http(Bob.Router, [], opts)

    children = [
      {Task.Supervisor, [name: Bob.Tasks]},
      Bob.Queue,
      Bob.Schedule
    ]

    opts = [strategy: :one_for_one, name: Bob.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp setup_docker() do
    if config = System.get_env("BOB_DOCKER_CONFIG") do
      File.mkdir_p!(Path.expand("~/.docker"))
      File.write!(Path.expand("~/.docker/config.json"), config)
    end
  end

  defp setup_gsutil() do
    if credentials = System.get_env("BOB_GCP_CREDENTIALS") do
      File.mkdir_p!("/boto")
      File.write!("/boto/keyfile.json", credentials)
    end
  end

  defp port() do
    if port = System.get_env("BOB_PORT") do
      String.to_integer(port)
    else
      4003
    end
  end
end

defmodule Bob.Application do
  use Application

  def start(_type, _args) do
    opts = [port: port(), compress: true]

    setup_docker()
    setup_gsutil()
    setup_tarsnap()
    validate_jobs()

    File.mkdir_p!(Bob.tmp_dir())

    # TODO: Do not start webserver if we are an agent
    Plug.Adapters.Cowboy.http(Bob.Router, [], opts)

    children = [
      {Task.Supervisor, [name: Bob.Tasks]},
      Bob.Queue,
      Bob.Runner,
      {Bob.Schedule, [schedule()]}
    ]

    opts = [strategy: :one_for_one, name: Bob.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp port() do
    if port = System.get_env("BOB_PORT") do
      String.to_integer(port)
    else
      4003
    end
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

  defp setup_tarsnap() do
    if key = System.get_env("BOB_TARSNAP_KEY") do
      File.mkdir_p!("/tarsnap")
      File.write!("/tarsnap/key", key)
    end
  end

  defp validate_jobs() do
    validate_jobs(Application.get_env(:bob, :local_jobs))
    validate_jobs(Application.get_env(:bob, :remote_jobs))
  end

  defp validate_jobs(jobs) do
    true = Enum.all?(jobs, &Code.ensure_loaded?/1)
  end

  defp schedule() do
    if Application.get_env(:bob, :master?) do
      Application.get_env(:bob, :master_schedule)
    else
      Application.get_env(:bob, :agent_schedule)
    end
  end
end

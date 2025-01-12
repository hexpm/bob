defmodule Bob.Application do
  use Application

  def start(_type, _args) do
    opts = [port: port(), compress: true]

    :logger.add_handler(:sentry_handler, Sentry.LoggerHandler, %{})

    setup_docker()
    setup_gsutil()
    setup_tarsnap()
    auth_docker()
    validate_jobs()

    File.mkdir_p!(Bob.tmp_dir())

    # TODO: Do not start webserver if we are an agent
    Plug.Cowboy.http(Bob.Router, [], opts)

    children = [
      {Task.Supervisor, [name: Bob.Tasks]},
      Bob.DockerHub.Auth,
      Bob.DockerHub.Cache,
      Bob.Queue,
      runner_spec(),
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
      config = fix_env_newlines(config)
      File.mkdir_p!(Path.expand("~/.docker"))
      File.write!(Path.expand("~/.docker/config.json"), config)
    end
  end

  defp setup_gsutil() do
    if credentials = System.get_env("BOB_GCP_CREDENTIALS") do
      credentials = fix_env_newlines(credentials)
      File.mkdir_p!("/boto")
      File.write!("/boto/keyfile.json", credentials)
    end
  end

  defp setup_tarsnap() do
    if key = System.get_env("BOB_TARSNAP_KEY") do
      key = fix_env_newlines(key)
      File.mkdir_p!("/tarsnap")
      # Tarsnap requires a newline before EOF, we should fix this at the source
      File.write!("/tarsnap/key", key <> "\n")
    end
  end

  defp auth_docker() do
    username = Application.get_env(:bob, :dockerhub_username)
    password = Application.get_env(:bob, :dockerhub_password)

    if username && password do
      {_, 0} =
        System.cmd("docker", ~w(login docker.io --username #{username} --password #{password}),
          stderr_to_stdout: true,
          parallelism: true
        )
    end
  end

  defp fix_env_newlines(string) do
    if System.get_env("BOB_FIX_ENV_NEWLINES") do
      # This is an artifact from using docker .env files which don't support \n
      string
      |> String.replace(~r"(?<!\\)\\n", "\n")
      |> String.replace("\\\\n", "\\n")
    else
      string
    end
  end

  defp validate_jobs() do
    validate_jobs(Application.get_env(:bob, :local_jobs))
    validate_jobs(Application.get_env(:bob, :remote_jobs))
  end

  defp validate_jobs(jobs) do
    true =
      Enum.all?(jobs, fn
        {module, _key} -> Code.ensure_loaded?(module)
        module -> Code.ensure_loaded?(module)
      end)
  end

  if Mix.env() == :test do
    defp runner_spec(), do: Supervisor.child_spec({Task, fn -> :ok end}, id: :runner)
  else
    defp runner_spec(), do: Bob.Runner
  end

  defp schedule() do
    if Application.get_env(:bob, :master?) do
      Application.get_env(:bob, :master_schedule)
    else
      Application.get_env(:bob, :agent_schedule)
    end
  end
end

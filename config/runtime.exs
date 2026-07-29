import Config

if config_env() == :prod do
  jobs_fun = fn env ->
    {result, _bindings} = Code.eval_string(System.fetch_env!(env))
    result
  end

  # Both default to the narrowest setting, so an unset variable can only ever
  # mean "report, delete nothing" rather than a live run nobody asked for.
  cleanup_mode = fn ->
    case System.get_env("BOB_DOCKER_CLEANUP_MODE", "dry_run") do
      "live" -> :live
      _other -> :dry_run
    end
  end

  cleanup_scope = fn ->
    "BOB_DOCKER_CLEANUP_SCOPE"
    |> System.get_env("per_arch")
    |> String.split(",", trim: true)
    |> Enum.map(&(&1 |> String.trim() |> String.to_atom()))
  end

  config :bob,
    github_user: System.fetch_env!("BOB_GITHUB_USER"),
    github_token: System.fetch_env!("BOB_GITHUB_TOKEN"),
    dockerhub_username: System.get_env("BOB_DOCKERHUB_USERNAME"),
    dockerhub_password: System.get_env("BOB_DOCKERHUB_PASSWORD"),
    agent_secret: System.fetch_env!("BOB_AGENT_SECRET"),
    master_url: System.fetch_env!("BOB_MASTER_URL"),
    master?: System.fetch_env!("BOB_WHO") == "master",
    parallel_jobs: String.to_integer(System.fetch_env!("BOB_PARALLEL_JOBS")),
    local_jobs: jobs_fun.("BOB_LOCAL_JOBS"),
    remote_jobs: jobs_fun.("BOB_REMOTE_JOBS"),
    hexpm_url: System.get_env("BOB_HEXPM_URL", "https://hex.pm"),
    oauth_client_id: System.fetch_env!("BOB_OAUTH_CLIENT_ID"),
    oauth_client_secret: System.fetch_env!("BOB_OAUTH_CLIENT_SECRET"),
    docker_cleanup_mode: cleanup_mode.(),
    docker_cleanup_scope: cleanup_scope.()

  config :ex_aws,
    access_key_id: System.fetch_env!("BOB_S3_ACCESS_KEY"),
    secret_access_key: System.fetch_env!("BOB_S3_SECRET_KEY")

  config :sentry,
    dsn: System.fetch_env!("BOB_SENTRY_DSN"),
    environment_name: System.fetch_env!("BOB_ENV"),
    tags: %{
      bob_who: System.fetch_env!("BOB_WHO"),
      bob_hostname: System.fetch_env!("BOB_HOSTNAME")
    }

  if metrics_port = System.get_env("BOB_METRICS_PORT") do
    config :bob, metrics_port: String.to_integer(metrics_port)
  end

  bob_host = System.fetch_env!("BOB_HOST")

  config :bob, BobWeb.Endpoint,
    server: true,
    url: [host: bob_host, port: 443, scheme: "https"],
    http: [ip: {0, 0, 0, 0}, port: String.to_integer(System.get_env("BOB_PORT") || "4003")],
    secret_key_base: System.fetch_env!("SECRET_KEY_BASE"),
    check_origin: ["https://#{bob_host}"]
end

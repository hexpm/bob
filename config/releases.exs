import Config

jobs_fun = fn env ->
  {result, _bindings} = Code.eval_string(System.fetch_env!(env))
  result
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
  remote_jobs: jobs_fun.("BOB_REMOTE_JOBS")

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

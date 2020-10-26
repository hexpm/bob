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

config :rollbax,
  access_token: System.fetch_env!("BOB_ROLLBAR_ACCESS_TOKEN"),
  custom: %{
    "bob-who" => System.fetch_env!("BOB_WHO"),
    "bob-hostname" => System.fetch_env!("BOB_HOSTNAME")
  }

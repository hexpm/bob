use Mix.Config

config :bob,
  tmp_dir: "/tmp",
  github_secret: "${BOB_GITHUB_SECRET}",
  github_user: "${BOB_GITHUB_USER}",
  github_token: "${BOB_GITHUB_TOKEN}"

config :ex_aws,
  access_key_id: {:system, "BOB_S3_ACCESS_KEY"},
  secret_access_key: {:system, "BOB_S3_SECRET_KEY"}

config :logger, level: :info

config :rollbax,
  access_token: "${BOB_ROLLBAR_ACCESS_TOKEN}",
  environment: to_string(Mix.env()),
  enabled: true,
  enable_crash_reports: true

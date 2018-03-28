use Mix.Config

config :logger, level: :info

config :rollbax,
  access_token: System.get_env("BOB_ROLLBAR_ACCESS_TOKEN"),
  environment: to_string(Mix.env()),
  enabled: !!System.get_env("BOB_ROLLBAR_ACCESS_TOKEN"),
  enable_crash_reports: true

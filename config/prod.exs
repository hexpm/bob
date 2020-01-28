import Config

config :bob,
  tmp_dir: "/tmp",
  persist_dir: "/persist"

config :logger, level: :info

config :rollbax,
  environment: to_string(Mix.env()),
  enabled: true,
  enable_crash_reports: true

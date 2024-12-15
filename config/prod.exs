import Config

config :bob,
  tmp_dir: "/tmp",
  persist_dir: "/persist"

config :logger, level: :info

config :sentry,
  enable_source_code_context: true,
  root_source_code_paths: [File.cwd!()]

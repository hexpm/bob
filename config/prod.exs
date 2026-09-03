import Config

config :bob,
  tmp_dir: "/tmp",
  persist_dir: "/persist"

config :bob, BobWeb.Endpoint, cache_static_manifest: "priv/static/cache_manifest.json"

config :logger, level: :info

config :logger, :default_handler,
  formatter:
    {LoggerJSON.Formatters.GoogleCloud,
     metadata: {:from_application_env, {:bob, :log_metadata}},
     reported_levels: [],
     project_id: nil}

config :sentry,
  enable_source_code_context: true,
  root_source_code_paths: [File.cwd!()]

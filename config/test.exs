import Config

config :bob,
  master_schedule: [],
  agent_schedule: []

config :ex_aws,
  access_key_id: "test",
  secret_access_key: "test",
  http_client: Bob.FakeHttpClient

config :logger, level: :warning

config :bob, Bob.Repo,
  username: System.get_env("POSTGRES_USER", "postgres"),
  password: System.get_env("POSTGRES_PASSWORD", "postgres"),
  hostname: System.get_env("POSTGRES_HOST", "localhost"),
  database: "bob_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

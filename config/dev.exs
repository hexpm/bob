import Config

config :bob,
  master_schedule: [],
  agent_schedule: []

config :bob, Bob.Repo,
  username: System.get_env("POSTGRES_USER", "postgres"),
  password: System.get_env("POSTGRES_PASSWORD", "postgres"),
  hostname: System.get_env("POSTGRES_HOST", "localhost"),
  database: "bob_dev",
  pool_size: 10

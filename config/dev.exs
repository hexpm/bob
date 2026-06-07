import Config

config :bob,
  master_schedule: [],
  agent_schedule: []

config :bob, Bob.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "bob_dev",
  pool_size: 10

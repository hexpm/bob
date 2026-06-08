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
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "bob_test",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

config :bob, BobWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "tT9wQ2eR5yU8iO1pA4sD7fG0hJ3kL6zX9cV2bN5mQ8wE1rT4yU7iO0pA3sD6fG90",
  server: false

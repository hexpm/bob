import Config

config :bob,
  master_schedule: [],
  agent_schedule: []

config :ex_aws,
  access_key_id: "test",
  secret_access_key: "test",
  http_client: Bob.FakeHttpClient

config :logger, level: :warning

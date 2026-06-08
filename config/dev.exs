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

config :bob, BobWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4003],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "kQv8mZr2hP0sJX4bN6wL9cT1dY3fA5gH7uE2iO4kR6mS8tV0xZ2bC4dF6hJ8lN09",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:bob, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:bob, ~w(--watch)]}
  ],
  live_reload: [
    patterns: [
      ~r"priv/static/.*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"lib/bob_web/(controllers|live|components)/.*(ex|heex)$"
    ]
  ]

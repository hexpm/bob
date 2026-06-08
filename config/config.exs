import Config

config :bob, ecto_repos: [Bob.Repo]

config :bob,
  master_schedule: [
    # Elixir builds and the Elixir standard-library docs are produced by
    # https://github.com/elixir-lang/elixir/blob/main/.github/workflows/release.yml,
    # so Bob no longer schedules them.
    [
      module: Bob.Job.OTPChecker,
      args: [:tags],
      period: {15, :min},
      queue: true
    ],
    [
      module: Bob.Job.OTPChecker,
      args: [:branches],
      period: :day,
      time: {3, 0, 0},
      queue: true
    ],
    [
      module: Bob.Job.DockerChecker,
      period: {15, :min},
      queue: true
    ],
    [
      module: Bob.Job.Reconcile,
      period: :day,
      time: {1, 0, 0},
      queue: true
    ],
    [
      module: Bob.Job.ReconcileBaseImages,
      period: {1, :hour},
      queue: true
    ]
  ],
  agent_schedule: [
    [
      module: Bob.Job.Clean,
      period: {1, :hour}
    ]
  ]

config :bob,
  tmp_dir: "tmp",
  persist_dir: "persist",
  master?: true,
  parallel_jobs: 1,
  local_jobs: [],
  remote_jobs: []

config :mime, :types, %{
  "application/vnd.bob+erlang" => ["erlang"]
}

config :porcelain, driver: Porcelain.Driver.Basic

config :ex_aws, http_client: ExAws.Request.Req

config :sentry, client: Bob.SentryClient

config :logger, :default_formatter, format: "$metadata[$level] $message\n"

config :bob, BobWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: BobWeb.ErrorHTML, json: BobWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Bob.PubSub,
  live_view: [signing_salt: "u8xQ2rPspeARxr1n"]

config :phoenix, :json_library, JSON

config :esbuild,
  version: "0.21.5",
  bob: [
    args: ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

config :tailwind,
  version: "3.4.3",
  bob: [
    args:
      ~w(--config=tailwind.config.js --input=css/app.css --output=../priv/static/assets/app.css),
    cd: Path.expand("../assets", __DIR__)
  ]

import_config "#{Mix.env()}.exs"

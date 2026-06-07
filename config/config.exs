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

config :logger, :default_formatter, format: "$metadata[$level] $message\n"

import_config "#{Mix.env()}.exs"

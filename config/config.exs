import Config

config :bob,
  master_schedule: [
    [
      module: Bob.Job.Backup,
      period: :day,
      time: {2, 0, 0},
      queue: true
    ],
    [
      module: Bob.Job.ElixirChecker,
      period: {15, :min}
    ],
    [
      module: Bob.Job.ElixirGuidesChecker,
      period: {15, :min}
    ],
    [
      module: Bob.Job.HexDocsChecker,
      period: {15, :min}
    ],
    [
      module: Bob.Job.OTPChecker,
      args: [:tags],
      period: {15, :min}
    ],
    [
      module: Bob.Job.OTPChecker,
      args: [:branches],
      period: :day,
      time: {3, 0, 0}
    ],
    [
      module: Bob.Job.DockerChecker,
      args: [:erlang],
      period: {15, :min}
    ],
    [
      module: Bob.Job.DockerChecker,
      args: [:elixir],
      period: {15, :min}
    ],
    [
      module: Bob.Job.DockerChecker,
      args: [:manifest],
      period: {15, :min}
    ]
  ],
  agent_schedule: [
    [
      module: Bob.Job.Clean,
      period: {6, :hour},
      queue: true
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

config :logger, :console, format: "$metadata[$level] $message\n"

config :rollbax, enabled: false

import_config "#{Mix.env()}.exs"

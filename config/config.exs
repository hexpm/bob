import Config

config :bob,
  master_schedule: [
    [
      module: Bob.Job.Clean,
      period: :day,
      time: {4, 0, 0}
    ],
    [
      module: Bob.Job.Backup,
      period: :day,
      time: {2, 0, 0}
    ],
    [
      module: Bob.Job.ElixirChecker,
      period: {15, :min},
      queue: false
    ],
    [
      module: Bob.Job.ElixirGuidesChecker,
      period: {15, :min},
      queue: false
    ],
    [
      module: Bob.Job.HexDocsChecker,
      period: {15, :min},
      queue: false
    ],
    [
      module: Bob.Job.OTPChecker,
      args: [:tags],
      period: {15, :min},
      queue: false
    ],
    [
      module: Bob.Job.OTPChecker,
      args: [:branches],
      period: :day,
      time: {3, 0, 0},
      queue: false
    ],
    [
      module: Bob.Job.DockerChecker,
      period: {15, :min},
      queue: false
    ],
    [
      module: Bob.Job.QueueChecker,
      args: [:master],
      period: {1, :sec},
      queue: false,
      log: false
    ]
  ],
  agent_schedule: [
    [
      module: Bob.Job.Clean,
      period: :day,
      time: {4, 0, 0}
    ],
    [
      module: Bob.Job.QueueChecker,
      args: [:agent],
      period: {1, :min},
      queue: false,
      log: false
    ]
  ]

config :bob,
  tmp_dir: "tmp",
  persist_dir: "persist",
  master?: true,
  local_jobs: [],
  remote_jobs: []

config :mime, :types, %{
  "application/vnd.bob+erlang" => ["erlang"]
}

config :porcelain, driver: Porcelain.Driver.Basic

config :logger, :console, format: "$metadata[$level] $message\n"

config :rollbax, enabled: false

import_config "#{Mix.env()}.exs"

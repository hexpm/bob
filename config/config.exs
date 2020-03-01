import Config

config :bob,
  schedule: [
    [
      module: Bob.Job.Clean,
      args: [],
      period: :day,
      time: {4, 0, 0}
    ],
    [
      module: Bob.Job.Backup,
      args: [],
      period: :day,
      time: {2, 0, 0}
    ],
    [
      module: Bob.Job.ElixirChecker,
      args: [],
      period: {15, :min}
    ],
    [
      module: Bob.Job.ElixirGuidesChecker,
      args: [],
      period: {15, :min}
    ],
    [
      module: Bob.Job.HexDocsChecker,
      args: [],
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
      args: [],
      period: {15, :min}
    ]
  ]

config :bob,
  tmp_dir: "tmp",
  persist_dir: "persist"

config :porcelain, driver: Porcelain.Driver.Basic

config :logger, :console, format: "$metadata[$level] $message\n"

config :rollbax, enabled: false

import_config "#{Mix.env()}.exs"

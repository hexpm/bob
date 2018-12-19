use Mix.Config

config :bob,
  schedule: [
    [
      module: Bob.Job.BackupS3,
      args: [],
      period: :day,
      time: {2, 0, 0}
    ],
    [
      module: Bob.Job.BuildOTPChecker,
      args: [],
      period: {15, :min}
    ]
  ]

config :bob,
  tmp_dir: "tmp",
  persist_dir: "persist"

config :porcelain, driver: Porcelain.Driver.Basic

config :logger, :console,
  format: "$time $metadata[$level] $message\n"

config :rollbax, enabled: false

import_config "#{Mix.env()}.exs"

use Mix.Config

config :bob, :elixir,
  github:   [script: "elixir_github.sh"],
  build:    [cmd: "cd elixir && make"],
  zip:      [cmd: "cd elixir && make Precompiled.zip && mv *.zip build.zip"],
  periodic: [
    period: :day,
    time:   {0, 0, 0},
    action: [script: "elixir_docs.sh"]
  ]

config :bob, :hex,
  periodic: [
    period: :day,
    time:   {3, 0, 0},
    action: [script: "backup_s3.sh"],
    dir:    :persist
  ]

config :bob,
  repos:         %{"elixir-lang" => :elixir},
  periodic:      [elixir: :periodic, hex: :periodic],
# github_token:  System.get_env("BOB_GITHUB_TOKEN"),
  github_secret: System.get_env("BOB_GITHUB_SECRET")

config :porcelain,
  driver: Porcelain.Driver.Basic

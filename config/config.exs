use Mix.Config

config :bob, :elixir,
  github: [script: "elixir_github.sh"]

config :bob, :elixir_guides,
  github: [script: "elixir_guides_github.sh"]

config :bob, :hex,
  backup_s3: [
    period: :day,
    time: {3, 0, 0},
    action: [script: "backup_s3.sh"],
    dir: :persist
  ],
  backup_db: [
    period: :day,
    time: {2, 0, 0},
    action: [script: "backup_db.sh"],
    dir: :temp
  ]

config :bob,
  repos: %{
    "elixir-lang/elixir" => :elixir,
    "elixir-lang/elixir-lang.github.com" => :elixir_guides
  },
  periodic: [hex: :backup_s3, hex: :backup_db],
  github_secret: System.get_env("BOB_GITHUB_SECRET")
# github_token: System.get_env("BOB_GITHUB_TOKEN")

config :porcelain,
  driver: Porcelain.Driver.Basic

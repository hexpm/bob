use Mix.Config

config :bob, :elixir,
  github: [script: "elixir_github.sh"]

config :bob, :elixir_guides,
  github: [script: "elixir_guides_github.sh"]

config :bob, :hex,
  periodic: [
    period: :day,
    time: {3, 0, 0},
    action: [script: "backup_s3.sh"],
    dir: :persist
  ]

config :bob,
  repos: %{
    "elixir-lang/elixir" => :elixir,
    "elixir-lang/elixir-lang.github.com" => :elixir_guides
  },
  periodic: [hex: :periodic],
  github_secret: System.get_env("BOB_GITHUB_SECRET")
# github_token: System.get_env("BOB_GITHUB_TOKEN")

config :porcelain,
  driver: Porcelain.Driver.Basic

use Mix.Config

repos = %{
  "elixir-lang/elixir" => %{
    name: "elixir",
    git_url: "git://github.com/elixir-lang/elixir.git",
    build: ["cd elixir && make"],
    zip: ["cd elixir && make Precompiled.zip && mv *.zip build.zip"],
    docs: ["git clone git://github.com/elixir-lang/ex_doc.git --depth 1 --single-branch",
           "MIX_ARCHIVES=.mix elixir/bin/elixir elixir/bin/mix local.hex --force",
           "cd ex_doc && MIX_ARCHIVES=../.mix ../elixir/bin/elixir ../elixir/bin/mix do deps.get, compile",
           "git clone https://${BOB_GITHUB_TOKEN}@github.com/elixir-lang/docs.git",
           "cd elixir && make publish_docs",
           "cd docs && git add --all && git commit --allow-empty -m \"Nightly build\" && git push"],
    on: %{
      push: [:build, :zip],
      time: %{{2, 0, 0} => {24*60*60, "master", [:build, :docs]}}
    }
  }
}

config :bob,
  repos:         repos,
# github_token:  System.get_env("BOB_GITHUB_TOKEN"),
  github_secret: System.get_env("BOB_GITHUB_SECRET"),
  s3_bucket:     System.get_env("BOB_S3_BUCKET")

config :ex_aws,
  access_key_id:     {:system, "BOB_S3_ACCESS_KEY"},
  secret_access_key: {:system, "BOB_S3_SECRET_KEY"}

config :ex_aws, :httpoison_opts,
  recv_timeout: 30_000,
  hackney: [pool: true]

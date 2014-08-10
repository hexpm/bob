use Mix.Config

repos = %{
  "elixir-lang/elixir" => %{
    name: "elixir",
    git_url: "git://github.com/elixir-lang/elixir.git",
    build: ["cd elixir && make"],
    zip: ["cd elixir && make release_zip && mv *.zip build.zip"],
    docs: ["git clone git://github.com/elixir-lang/ex_doc.git --depth 1 --single-branch",
           "MIX_ARCHIVES=.mix elixir/bin/elixir elixir/bin/mix local.hex --force",
           "cd ex_doc && MIX_ARCHIVES=../.mix ../elixir/bin/elixir ../elixir/bin/mix do deps.get, compile",
           "git clone https://${BOB_GITHUB_TOKEN}@github.com/elixir-lang/docs.git",
           "cd elixir && make release_docs",
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
  s3_bucket:     System.get_env("BOB_S3_BUCKET"),
  s3_access_key: System.get_env("BOB_S3_ACCESS_KEY"),
  s3_secret_key: System.get_env("BOB_S3_SECRET_KEY")

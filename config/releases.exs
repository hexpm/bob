import Config

config :bob,
  github_secret: System.fetch_env!("BOB_GITHUB_SECRET"),
  github_user: System.fetch_env!("BOB_GITHUB_USER"),
  github_token: System.fetch_env!("BOB_GITHUB_TOKEN")

config :ex_aws,
  access_key_id: System.fetch_env!("BOB_S3_ACCESS_KEY"),
  secret_access_key: System.fetch_env!("BOB_S3_SECRET_KEY")

config :rollbax,
  access_token: System.fetch_env!("BOB_ROLLBAR_ACCESS_TOKEN"),

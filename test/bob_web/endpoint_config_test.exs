defmodule BobWeb.EndpointConfigTest do
  use ExUnit.Case, async: false

  @config_dir Path.expand("../../config", __DIR__)
  @prod_runtime_env %{
    "BOB_AGENT_SECRET" => "secret",
    "BOB_ENV" => "prod",
    "BOB_GITHUB_TOKEN" => "github-token",
    "BOB_GITHUB_USER" => "hexbob",
    "BOB_HOST" => "bob.hex.pm",
    "BOB_HOSTNAME" => "gce",
    "BOB_LOCAL_JOBS" => "[]",
    "BOB_MASTER_URL" => "https://bob.hex.pm",
    "BOB_PARALLEL_JOBS" => "10",
    "BOB_PORT" => "4003",
    "BOB_REMOTE_JOBS" => "[]",
    "BOB_S3_ACCESS_KEY" => "s3-key",
    "BOB_S3_SECRET_KEY" => "s3-secret",
    "BOB_SENTRY_DSN" => "https://public@example.com/1",
    "BOB_WHO" => "master",
    "SECRET_KEY_BASE" => String.duplicate("a", 64)
  }

  test "configured cookie session secret keys satisfy Plug's minimum length" do
    for env <- [:dev, :test] do
      endpoint_config =
        @config_dir
        |> Path.join("#{env}.exs")
        |> Config.Reader.read!(env: env)
        |> get_in([:bob, BobWeb.Endpoint])

      secret_key_base = Keyword.fetch!(endpoint_config, :secret_key_base)

      assert byte_size(secret_key_base) >= 64
    end
  end

  test "favicon assets are served as static paths" do
    assert "favicon.ico" in BobWeb.static_paths()
    assert "images" in BobWeb.static_paths()
  end

  test "prod runtime endpoint config uses a schemed LiveView origin" do
    with_env(@prod_runtime_env, fn ->
      endpoint_config =
        @config_dir
        |> Path.join("runtime.exs")
        |> Config.Reader.read!(env: :prod)
        |> get_in([:bob, BobWeb.Endpoint])

      assert Keyword.fetch!(endpoint_config, :url)[:host] == "bob.hex.pm"
      assert Keyword.fetch!(endpoint_config, :check_origin) == ["https://bob.hex.pm"]
    end)
  end

  defp with_env(env, fun) do
    previous = Map.new(Map.keys(env), &{&1, System.get_env(&1)})

    try do
      System.put_env(env)
      fun.()
    after
      for {key, value} <- previous do
        if value do
          System.put_env(key, value)
        else
          System.delete_env(key)
        end
      end
    end
  end
end

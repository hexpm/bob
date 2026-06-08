defmodule BobWeb.EndpointConfigTest do
  use ExUnit.Case, async: true

  @config_dir Path.expand("../../config", __DIR__)

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
    assert "images/favicon-64.png" in BobWeb.static_paths()
    assert "images/favicon-160.png" in BobWeb.static_paths()
  end
end

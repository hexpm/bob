defmodule Bob.Mixfile do
  use Mix.Project

  def project() do
    [
      app: :bob,
      version: "0.0.1",
      elixir: "~> 1.0",
      start_permanent: Mix.env() == :prod,
      build_embedded: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application() do
    [
      mod: {Bob, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp deps() do
    [
      {:plug, "~> 1.0"},
      {:cowboy, ">= 0.0.0"},
      {:poison, "~> 2.0"},
      {:porcelain, "~> 2.0"},
      {:hackney, "~> 1.11"},
      {:ex_aws_s3, "~> 2.0"},
      {:rollbax, "== 0.9.0"},
      {:distillery, "~> 1.5", runtime: false}
    ]
  end
end

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
      {:cowboy, "~> 1.0"},
      {:distillery, "~> 1.5", runtime: false},
      {:ex_aws_s3, "~> 2.0"},
      {:hackney, "~> 1.11"},
      {:jason, "~> 1.1"},
      {:plug, "~> 1.0"},
      {:poison, "~> 3.1"},
      {:porcelain, "~> 2.0"},
      {:rollbax, "== 0.9.0"},
      {:sweet_xml, "~> 0.5"}
    ]
  end
end

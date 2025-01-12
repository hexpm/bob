defmodule Bob.Mixfile do
  use Mix.Project

  def project() do
    [
      app: :bob,
      version: "0.0.1",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      build_embedded: Mix.env() == :prod,
      releases: releases(),
      deps: deps()
    ]
  end

  def application() do
    [
      mod: {Bob.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp deps() do
    [
      {:ex_aws_s3, "~> 2.0"},
      {:hackney, "~> 1.11"},
      {:jason, "~> 1.1"},
      {:plug_cowboy, "~> 2.0"},
      {:porcelain, "~> 2.0"},
      {:sentry, "~> 10.2"},
      {:sweet_xml, "~> 0.5"},
      {:logster, "~> 1.0"}
    ]
  end

  defp releases() do
    [
      bob: [
        include_executables_for: [:unix],
        reboot_system_after_config: true
      ]
    ]
  end
end

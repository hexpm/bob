defmodule Bob.Mixfile do
  use Mix.Project

  def project() do
    [
      app: :bob,
      version: "0.0.1",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      releases: releases(),
      aliases: aliases(),
      deps: deps()
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application() do
    [
      mod: {Bob.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp deps() do
    [
      {:ecto_sql, "~> 3.12"},
      {:ex_aws_s3, "~> 2.0"},
      {:finch, "~> 0.19"},
      {:req, "~> 0.5"},
      {:plug_cowboy, "~> 2.0"},
      {:porcelain, "~> 2.0"},
      {:postgrex, "~> 0.19"},
      {:sentry, "~> 10.2"},
      {:sweet_xml, "~> 0.5"},
      {:logster, "~> 1.0"},
      {:observer_cli, "~> 1.7"}
    ]
  end

  defp aliases() do
    [
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"]
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

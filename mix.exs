defmodule Bob.Mixfile do
  use Mix.Project

  def project() do
    [
      app: :bob,
      version: "0.0.1",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      listeners: [Phoenix.CodeReloader],
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
      {:tidewave, "~> 0.5", only: [:dev]},
      {:ecto_sql, "~> 3.12"},
      {:ex_aws_s3, "~> 2.0"},
      {:finch, "~> 0.19"},
      {:req, "~> 0.5"},
      {:porcelain, "~> 2.0"},
      {:postgrex, "~> 0.19"},
      {:sentry, "~> 10.2"},
      {:sweet_xml, "~> 0.5"},
      {:logster, "~> 1.0"},
      {:observer_cli, "~> 1.7"},
      {:phoenix_pubsub, "~> 2.1"},
      {:phoenix, "~> 1.7"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_view, "~> 1.0"},
      {:phoenix_live_reload, "~> 1.5", only: :dev},
      {:bandit, "~> 1.5"},
      {:esbuild, "~> 0.8", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.2", runtime: Mix.env() == :dev},
      {:igniter, "~> 0.8.1", only: [:dev, :test], runtime: false},
      {:lazy_html, ">= 0.1.0", only: :test}
    ]
  end

  defp aliases() do
    [
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["tailwind bob", "esbuild bob"],
      "assets.deploy": ["tailwind bob --minify", "esbuild bob --minify", "phx.digest"]
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

defmodule Bob.Mixfile do
  use Mix.Project

  def project do
    [app: :bob,
     version: "0.0.1",
     elixir: "~> 1.0",
     deps: deps]
  end

  # Configuration for the OTP application
  #
  # Type `mix help compile.app` for more information
  def application do
    [applications: [:cowboy, :plug, :poison, :mini_s3, :porcelain],
     mod: {Bob, []}]
  end

  # Dependencies can be hex.pm packages:
  #
  #   {:mydep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:mydep, git: "https://github.com/elixir-lang/mydep.git", tag: "0.1"}
  #
  # Type `mix help deps` for more examples and options
  defp deps do
    [{:plug, "~> 0.8.0"},
     {:cowboy, nil},
     {:poison, "~> 1.0"},
     {:mini_s3, github: "ericmj/mini_s3", branch: "hex-fixes"},
     {:porcelain, "~> 1.1"}]
  end
end

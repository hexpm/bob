#!/usr/bin/env elixir

[elixir, latest] = System.argv

case elixir do
  "v1.4"      -> "v#{latest}"
  "v1.3"      -> "v#{latest}"
  "v1.2"      -> "v0.14.1"
  "v1.1"      -> "v0.12.0"
  "v1.0"      -> "v0.12.0"
  "v" <> version ->
    case Version.parse(version) do
      {:ok, version} ->
        cond do
          Version.compare(version, "1.2.3") in [:eq, :gt] ->
            "v#{latest}"
          Version.compare(version, "1.2.0") in [:eq, :gt] ->
            "v0.14.1"
          Version.compare(version, "1.0.0") in [:eq, :gt] ->
            "v0.12.0"
          true ->
            "v#{latest}"
        end
      :error ->
        "v#{latest}"
    end
  # All branches use master
  _ ->
    "master"
end
|> IO.puts

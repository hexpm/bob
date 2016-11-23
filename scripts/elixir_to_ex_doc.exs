#!/usr/bin/env elixir

[elixir] = System.argv

case elixir do
  "v1.3"      -> "master"
  "v1.2"      -> "v0.14.1"
  "v1.1"      -> "v0.12.0"
  "v1.0"      -> "v0.12.0"
  "v" <> version ->
    case Version.parse(version) do
      {:ok, version} ->
        cond do
          Version.compare(version, "1.2.3") in [:eq, :gt] ->
            "master"
          Version.compare(version, "1.2.0") in [:eq, :gt] ->
            "v0.14.1"
          Version.compare(version, "1.0.0") in [:eq, :gt] ->
            "v0.12.0"
          true ->
            "master"
        end
      :error ->
        "master"
    end
  _ ->
    "master"
end
|> IO.puts

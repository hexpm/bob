#!/usr/bin/env elixir

[elixir] = System.argv

case elixir do
  "v1.0"      -> "17.5"
  "v1.0.5"    -> "17.5"
  "v1.0.4"    -> "17.5"
  "v0"   <> _ -> "17.3"
  "v1.0" <> _ -> "17.3"
  "v1.1" <> _ -> "17.5"
  "v" <> version ->
    case Version.parse(version) do
      {:ok, version} ->
        cond do
          Version.compare(version, "1.2.0-rc.0") in [:eq, :gt] ->
            "18.3"
          Version.compare(version, "1.0.4") in [:eq, :gt] ->
            "17.5"
          true ->
            "17.3"
        end
      :error ->
        # For v1.2, v1.3, ..., that fail the version parse
        "18.3"
    end
  _ ->
    "18.3"
end
|> IO.puts

[elixir] = System.argv

case elixir do
  "v1.0" -> "17"
  "v1.1" -> "17"
  "v" <> version ->
    case Version.parse(version) do
      {:ok, version} ->
        if Version.compare(version, "1.2.0-rc.0") in [:eq, :gt],
            do: "18",
          else: "17"
      :error ->
        # For v1.2, v1.3, ..., that fail the version parse
        "18"
    end
  _ ->
    "18"
end
|> IO.puts

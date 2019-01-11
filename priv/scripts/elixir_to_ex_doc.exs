#!/usr/bin/env elixir

[elixir, _latest] = System.argv

case elixir do
  "v1.7" <> _ -> "v0.19.1"
  "v1.6" <> _ -> "v0.18.3"
  "v1.5" <> _ -> "v0.18.3"
  "v1.4" <> _ -> "v0.16.1"
  "v1.3" <> _ -> "v0.16.1"
  "v1.2" <> _ -> "v0.14.5"
  "v1.1" <> _ -> "v0.12.0"
  "v1.0" <> _ -> "v0.12.0"
  # All branches use master
  _ -> "master"
end
|> IO.puts

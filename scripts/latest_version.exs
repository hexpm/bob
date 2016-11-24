#!/usr/bin/env elixir

System.argv
|> hd
|> String.split(" ", trim: true)
|> Enum.filter(&(String.at(&1, 0) == "v"))
|> Enum.map(fn "v" <> version -> version end)
|> Enum.filter(&match?({:ok, _}, Version.parse(&1)))
|> Enum.sort_by(&(&1), &(Version.compare(&1, &2) != :lt))
|> List.first
|> IO.puts

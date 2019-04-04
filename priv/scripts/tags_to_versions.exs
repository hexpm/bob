#!/usr/bin/env elixir

[tags, minimum_version] = System.argv()

tags
|> String.split(~r"(\s|\n)", trim: true)
|> Enum.filter(&(String.at(&1, 0) == "v"))
|> Enum.map(fn "v" <> version -> version end)
|> Enum.filter(&match?({:ok, _}, Version.parse(&1)))
|> Enum.filter(&Version.compare(&1, minimum_version) in [:gt, :eq])
|> Enum.sort_by(&(&1), &(Version.compare(&1, &2) != :lt))
|> Enum.join(" ")
|> IO.puts()

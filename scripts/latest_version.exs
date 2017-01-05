#!/usr/bin/env elixir

versions =
  System.argv
  |> hd
  |> String.split(~r"(\s|\n)", trim: true)
  |> Enum.filter(&(String.at(&1, 0) == "v"))
  |> Enum.map(fn "v" <> version -> version end)
  |> Enum.filter(&match?({:ok, _}, Version.parse(&1)))
  |> Enum.sort_by(&(&1), &(Version.compare(&1, &2) != :lt))

stable =
  versions
  |> Enum.filter(&(elem(Version.parse(&1), 1).pre == []))
  |> List.first

(stable || List.first(versions))
|> IO.puts

defmodule Bob.Job.DockerTxtUpdater do
  @moduledoc """
  A job to update the builds/docker/*.txt files with the latest tag information
  from Docker Hub.

  Creates the following files:

  https://builds.hex.pm/builds/docker/erlang:VERSION.txt
  https://builds.hex.pm/builds/docker/erlang-amd64:VERSION.txt
  https://builds.hex.pm/builds/docker/erlang-arm64:VERSION.txt
  https://builds.hex.pm/builds/docker/elixir:VERSION-erlang-VERSION.txt
  https://builds.hex.pm/builds/docker/elixir-amd64:VERSION-erlang-VERSION.txt
  https://builds.hex.pm/builds/docker/elixir-arm64:VERSION-erlang-VERSION.txt

  https://builds.hex.pm/builds/docker/erlang:x.y.txt
  https://builds.hex.pm/builds/docker/erlang-amd64:x.y.txt
  https://builds.hex.pm/builds/docker/erlang-arm64:x.y.txt
  https://builds.hex.pm/builds/docker/elixir:x.y-erlang-x.y.txt
  https://builds.hex.pm/builds/docker/elixir-amd64:x.y-erlang-x.y.txt
  https://builds.hex.pm/builds/docker/elixir-arm64:x.y-erlang-x.y.txt

  The x.y files list all the latest major + minor tag combinations, for example:

  ```
  # For elixir:x.y-erlang-x.y.txt
  1.19.5-erlang-28.3.1
  1.19.5-erlang-28.2
  1.19.5-erlang-28.1.1
  1.19.5-erlang-28.0.4
  1.19.5-erlang-27.3.4.7
  1.19.5-erlang-27.2.4
  1.19.5-erlang-27.1.3
  1.19.5-erlang-27.0.1
  1.19.5-erlang-26.2.5.16
  1.19.5-erlang-26.1.2
  1.19.5-erlang-26.0.2
  1.18.4-erlang-28.3.1
  1.18.4-erlang-28.2
  1.18.4-erlang-28.1.1
  1.18.4-erlang-28.0.4
  1.18.4-erlang-27.3.4.7
  1.18.4-erlang-27.2.4
  1.18.4-erlang-27.1.3
  1.18.4-erlang-27.0.1
  1.18.4-erlang-26.2.5.16
  1.18.4-erlang-26.1.2
  1.18.4-erlang-26.0.2
  1.18.4-erlang-25.3.2.21
  1.18.4-erlang-25.2.3
  1.18.4-erlang-25.1.2.1
  1.18.4-erlang-25.0.4
  1.17.3-erlang-27.3.4.7
  ```

  Which can then be looked up in `https://builds.hex.pm/builds/docker/elixir:1.19.5-erlang-28.3.1.txt

  ```
  # elixir:1.19.5-erlang-28.3.1.txt
  1.19.5-erlang-28.3.1-ubuntu-noble-20260210.1 amd64,arm64
  1.19.5-erlang-28.3.1-debian-trixie-20260202-slim amd64,arm64
  1.19.5-erlang-28.3.1-debian-bookworm-20260202-slim amd64,arm64
  1.19.5-erlang-28.3.1-debian-bookworm-20260202 amd64,arm64
  1.19.5-erlang-28.3.1-debian-trixie-20260202 amd64,arm64
  1.19.5-erlang-28.3.1-debian-bullseye-20260202-slim amd64,arm64
  1.19.5-erlang-28.3.1-debian-bullseye-20260202 amd64,arm64
  1.19.5-erlang-28.3.1-alpine-3.23.3 amd64,arm64
  1.19.5-erlang-28.3.1-alpine-3.22.3 amd64,arm64
  1.19.5-erlang-28.3.1-alpine-3.21.6 amd64,arm64
  1.19.5-erlang-28.3.1-alpine-3.20.9 amd64,arm64
  1.19.5-erlang-28.3.1-ubuntu-noble-20260113 amd64,arm64
  1.19.5-erlang-28.3.1-ubuntu-jammy-20260109 amd64,arm64
  1.19.5-erlang-28.3.1-ubuntu-focal-20250404 amd64,arm64
  1.19.5-erlang-28.3.1-debian-bullseye-20260112-slim amd64,arm64
  1.19.5-erlang-28.3.1-debian-bullseye-20260112 amd64,arm64
  1.19.5-erlang-28.3.1-debian-bookworm-20260112-slim amd64,arm64
  1.19.5-erlang-28.3.1-debian-trixie-20260112-slim amd64,arm64
  1.19.5-erlang-28.3.1-debian-trixie-20260112 amd64,arm64
  1.19.5-erlang-28.3.1-debian-bookworm-20260112 amd64,arm64
  1.19.5-erlang-28.3.1-alpine-3.22.2 amd64,arm64
  1.19.5-erlang-28.3.1-alpine-3.21.5 amd64,arm64
  1.19.5-erlang-28.3.1-alpine-3.20.8 amd64,arm64
  1.19.5-erlang-28.3.1-alpine-3.23.2 amd64,arm64
  ```
  """

  @erlang_tag_regex ~r"^(.+)-(alpine|ubuntu|debian)-(.+)$"
  @elixir_tag_regex ~r"^(.+)-erlang-(.+)-(alpine|ubuntu|debian)-(.+)$"

  @archs ["amd64", "arm64"]

  def run do
    update_erlang()
    update_elixir()
  end

  defp update_erlang do
    repos = ["hexpm/erlang" | Enum.map(@archs, &"hexpm/erlang-#{&1}")]

    Enum.each(repos, fn repo ->
      # %{"28.3.1" => [
      #    {"28.3.1", "erlang-28.3.1-ubuntu-noble-20260210.1", ["amd64", "arm64"]},
      #    {"28.3.1", "erlang-28.3.1-debian-trixie-20260202-slim", ["amd64", "arm64"]},
      #    {"28.3.1", "erlang-28.3.1-debian-bookworm-20260202-slim", ["amd64", "arm64"]},
      #    ...
      #  ],
      #  ...
      # }
      grouped =
        repo
        |> Bob.DockerHub.fetch_repo_tags_from_cache()
        |> Stream.map(fn {tag, architectures} ->
          ["erlang-" <> erlang, _os, _os_version] =
            Regex.run(@erlang_tag_regex, tag, capture: :all_but_first)

          {erlang, tag, architectures}
        end)
        |> Enum.group_by(fn {erlang, _tag, _architectures} ->
          erlang
        end)

      grouped
      |> Task.async_stream(fn {erlang, group} ->
        content =
          Enum.map_join(group, "\n", fn {_erlang, tag, architectures} ->
            "#{tag} #{Enum.join(architectures, ",")}"
          end)

        key = "builds/docker/" <> String.trim_leading(repo, "hexpm/") <> ":" <> erlang <> ".txt"

        Bob.Repo.write_file(key, content)
      end)
      |> Stream.run()

      x_y =
        grouped
        |> Map.keys()
        |> find_latest_erlang_major_minor()
        |> Enum.flat_map(fn version ->
          grouped = Map.fetch!(grouped, version)
          Enum.map(grouped, fn {_erlang, tag, _archs} -> tag end)
        end)

      key = "builds/docker/" <> String.trim_leading(repo, "hexpm/") <> ":x.y.txt"
      Bob.Repo.write_file(key, Enum.join(x_y, "\n"))
    end)
  end

  defp update_elixir do
    repos = ["hexpm/elixir" | Enum.map(@archs, &"hexpm/elixir-#{&1}")]

    Enum.each(repos, fn repo ->
      # %{
      #   {"1.15.7", "26.1.2"} => [
      #     {"1.15.7", "26.1.2", "1.15.7-erlang-26.1.2-ubuntu-noble-20260210.1",
      #      ["amd64", "arm64"]},
      #     {"1.15.7", "26.1.2", "1.15.7-erlang-26.1.2-debian-bullseye-20260202-slim",
      #      ["amd64", "arm64"]},
      #     ...
      #   ]
      # }
      grouped =
        repo
        |> Bob.DockerHub.fetch_repo_tags_from_cache()
        |> Stream.map(fn {tag, architectures} ->
          [elixir, erlang, _os, _os_version] =
            Regex.run(@elixir_tag_regex, tag, capture: :all_but_first)

          {elixir, erlang, tag, architectures}
        end)
        |> Enum.group_by(fn {elixir, erlang, _tag, _architectures} ->
          {elixir, erlang}
        end)

      grouped
      |> Task.async_stream(fn {{elixir, erlang}, group} ->
        content =
          Enum.map_join(group, "\n", fn {_elixir, _erlang, tag, architectures} ->
            "#{tag} #{Enum.join(architectures, ",")}"
          end)

        key =
          "builds/docker/" <>
            String.trim_leading(repo, "hexpm/") <> ":" <> elixir <> "-erlang-" <> erlang <> ".txt"

        Bob.Repo.write_file(key, content)
      end)
      |> Stream.run()

      x_y =
        grouped
        |> Map.keys()
        |> find_latest_elixir_and_erlang_major_minor()

      key = "builds/docker/" <> String.trim_leading(repo, "hexpm/") <> ":x.y-erlang-x.y.txt"
      Bob.Repo.write_file(key, Enum.join(x_y, "\n"))
    end)
  end

  defp find_latest_erlang_major_minor(versions) do
    versions
    |> Enum.map(&to_matchable/1)
    |> Enum.filter(fn {_major, pre} -> pre == [] end)
    |> Enum.group_by(fn {[major, minor | _rest], _pre} -> {major, minor} end)
    |> Enum.map(fn {_group, versions} ->
      Enum.max_by(versions, &Function.identity/1, &(cmp_erlang_components(&1, &2) != :lt), nil)
    end)
    # we sort so the file always contains the most recent version at the top
    |> Enum.sort(&(cmp_erlang_components(&1, &2) != :lt))
    |> Enum.map(fn {c, _} -> Enum.join(c, ".") end)
  end

  defp to_matchable(string) do
    destructure [version, pre], String.split(string, "-", parts: 2)

    components =
      version
      |> String.split(".")
      |> Enum.map(&String.to_integer/1)

    {components, pre || []}
  end

  defp cmp_erlang_components({[left | lefts], left_pre}, {[right | rights], right_pre}) do
    cond do
      left > right -> :gt
      left < right -> :lt
      true -> cmp_erlang_components({lefts, left_pre}, {rights, right_pre})
    end
  end

  defp cmp_erlang_components({[], left_pre}, {[], right_pre}) do
    cond do
      left_pre == [] and right_pre != [] -> :gt
      left_pre != [] and right_pre == [] -> :lt
      left_pre > right_pre -> :gt
      left_pre < right_pre -> :lt
      true -> :eq
    end
  end

  defp cmp_erlang_components({[], _left_pre}, {_rights, _right_pre}) do
    :lt
  end

  defp cmp_erlang_components({_lefts, _left_pre}, {[], _right_pre}) do
    :gt
  end

  defp find_latest_elixir_and_erlang_major_minor(versions) do
    versions
    |> Enum.map(fn {elixir, erlang} ->
      parsed_erl = to_matchable(erlang)
      {Version.parse!(normalize_version(elixir)), parsed_erl}
    end)
    |> Enum.filter(fn {vsn, {_erl_major, erl_pre}} -> vsn.pre == [] and erl_pre == [] end)
    |> Enum.group_by(fn {vsn, _} -> {vsn.major, vsn.minor} end)
    |> Enum.flat_map(fn {_group, versions} ->
      {max_elixir, _} =
        Enum.max_by(versions, &Function.identity/1, fn {x1, _e1}, {x2, _e2} ->
          Version.compare(x1, x2) != :lt
        end)

      versions
      |> Enum.filter(fn {elixir, _} -> elixir == max_elixir end)
      |> Enum.group_by(fn {_elixir, {[erl_major, erl_minor | _], _}} ->
        {erl_major, erl_minor}
      end)
      |> Enum.map(fn {_group, versions} ->
        Enum.max_by(versions, &Function.identity/1, fn {_, e1}, {_, e2} ->
          cmp_erlang_components(e1, e2) != :lt
        end)
      end)
    end)
    # we sort Elixir + Erlang descending
    |> Enum.sort(fn {x1, e1}, {x2, e2} ->
      case Version.compare(x1, x2) do
        :eq -> cmp_erlang_components(e1, e2)
        other -> other
      end != :lt
    end)
    |> Enum.map(fn {elixir, {erl, _}} ->
      "#{Version.to_string(elixir)}-erlang-#{Enum.join(erl, ".")}"
    end)
  end

  defp normalize_version(version) do
    case String.split(version, ".") do
      [major, minor] -> "#{major}.#{minor}.0"
      [_major, _minor | _rest] -> version
      _ -> version
    end
  end
end

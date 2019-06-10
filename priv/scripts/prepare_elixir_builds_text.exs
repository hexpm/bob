# Usage:
#
#    cd /path/to/bob
#    rm -rf tmp && mkdir tmp && cd tmp
#    aws s3 ls s3://s3.hex.pm/builds/elixir --recursive | grep -v builds.txt > elixir-ls.txt
#    aws s3 cp s3://s3.hex.pm/builds/elixir . --recursive
#    elixir ../priv/scripts/prepare_elixir_builds_text.exs
#    aws s3 cp builds.txt s3://s3.hex.pm/builds/elixir/builds.txt
#    curl -XPURGE https://repo.hex.pm/builds/elixir/builds.txt

defmodule Line do
  defstruct [:datetime, :path, :ref, :sha, :otp]

  def from_line(line) do
    pattern = ~r|builds/elixir/(.*?)(-otp-.*)?\.zip|

    [date, time, _, path] = String.split(line)

    [ref, otp] =
      case Regex.run(pattern, path, capture: :all_but_first) do
        [ref] -> [ref, ""]
        [ref, otp] -> [ref, otp]
      end

    %Line{
      datetime: "#{date}T#{time}Z",
      path: path,
      ref: ref,
      otp: otp
    }
  end

  def get_sha(line, repo_dir) do
    System.cmd("git", ["checkout", line.ref], cd: repo_dir)
    {sha, 0} = System.cmd("git", ["rev-parse", "HEAD"], cd: repo_dir)
    %{line | sha: String.trim(sha)}
  end

  def to_builds_txt(line) do
    [line.ref <> line.otp, line.sha, line.datetime] |> Enum.join(" ")
  end
end

# aws s3 ls s3://s3.hex.pm/builds/elixir --recursive
input = "elixir-ls.txt"
output = "builds.txt"
repo = "https://github.com/elixir-lang/elixir.git"
repo_dir = "elixir"

if !File.dir?(repo_dir) do
  System.cmd("git", ["clone", repo, repo_dir])
end

content =
  File.stream!(input)
  |> Enum.map(&Line.from_line/1)
  |> Enum.map(&Line.get_sha(&1, repo_dir))
  |> Enum.map_join("\n", &Line.to_builds_txt/1)

File.write!(output, content)
{_, 0} = System.cmd("sort", ["-u", "-k1,1", "-o", output, output])

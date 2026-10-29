defmodule Bob.OTPScriptTest do
  use ExUnit.Case

  @moduletag :tmp_dir

  setup %{tmp_dir: directory} do
    bin = Path.join(directory, "bin")
    state = Path.join(directory, "docker")
    File.mkdir_p!(bin)
    File.mkdir_p!(state)
    image_id = "sha256:" <> String.duplicate("a", 64)
    container_id = String.duplicate("b", 64)

    write_command(bin, "docker", ~S"""
    command=$1
    shift
    printf '%s %s\n' "$command" "$*" >> "$BOB_TEST_STATE/commands"
    [ "${BOB_TEST_FAIL:-}" != "$command" ] || exit 42

    case "$command" in
      build)
        while [ "$#" -gt 0 ]; do
          case "$1" in
            --iidfile) printf '%s\n' "$BOB_TEST_IMAGE_ID" > "$2"; shift ;;
          esac
          shift
        done
        ;;
      create) echo "$BOB_TEST_CONTAINER_ID" ;;
      start)
        if [ "${BOB_TEST_FAIL:-}" = term ]; then
          kill -TERM "$PPID"
        fi
        ;;
      cp) printf 'build\n' > "$2" ;;
      rm) exit 0 ;;
      *) echo "Unexpected docker command: $command" >&2; exit 1 ;;
    esac
    """)

    write_command(bin, "aws", "[ \"${BOB_TEST_FAIL:-}\" != aws ] || exit 42\n")
    write_command(bin, "curl", "exit 0\n")

    env = [
      {"PATH", bin <> ":" <> System.fetch_env!("PATH")},
      {"SCRIPT_DIR", Application.app_dir(:bob, "priv/scripts")},
      {"BOB_AGENT_SECRET", "test"},
      {"BOB_MASTER_URL", "http://bob.test"},
      {"BOB_TEST_STATE", state},
      {"BOB_TEST_IMAGE_ID", image_id},
      {"BOB_TEST_CONTAINER_ID", container_id}
    ]

    %{
      directory: directory,
      bin: bin,
      state: state,
      env: env,
      container_id: container_id
    }
  end

  for {stage, status} <- [{"start", 42}, {"cp", 42}, {"aws", 42}, {"term", 143}] do
    test "cleans up only its own container on #{stage}", context do
      assert {_output, unquote(status)} = build(context, fail: unquote(stage))

      assert Enum.filter(commands(context), &String.starts_with?(&1, "rm ")) == [
               "rm -f #{context.container_id}"
             ]
    end
  end

  for ref_name <- ["master", "OTP-29.1.1"] do
    test "downloads the queued commit and preserves the #{ref_name} artifact name", context do
      ref_name = unquote(ref_name)
      sha = String.duplicate("a", 40)

      for ref <- [sha, ref_name] do
        source = Path.join([context.state, "archives", "otp-#{ref}"])
        File.mkdir_p!(Path.join(source, "release/test"))
        File.write!(Path.join(source, "release/test/ref.txt"), ref)
        write_command(source, "otp_build", "exit 0\n")
        write_command(source, "configure", "exit 0\n")

        assert {_, 0} =
                 System.cmd("tar", ["-czf", "#{ref}.tar.gz", "otp-#{ref}"],
                   cd: Path.dirname(source),
                   stderr_to_stdout: true
                 )
      end

      write_command(context.bin, "wget", ~S"""
      url=${!#}
      printf '%s\n' "$url" > "$BOB_TEST_STATE/download"
      cp "$BOB_TEST_STATE/archives/${url##*/}" .
      """)

      write_command(context.bin, "make", "exit 0\n")
      directory = Path.join(context.directory, "compile")
      File.mkdir_p!(Path.join(directory, "out"))

      assert {_output, 0} =
               script("otp/build_otp_ubuntu.sh", [], directory, [
                 {"OTP_REF", ref_name},
                 {"OTP_SHA", sha},
                 {"UBUNTU_VERSION", "22.04"} | context.env
               ])

      assert File.read!(Path.join(context.state, "download")) ==
               "https://github.com/erlang/otp/archive/#{sha}.tar.gz\n"

      assert {^sha, 0} =
               System.cmd("tar", ["-xzOf", "out/#{ref_name}.tar.gz", "#{ref_name}/ref.txt"],
                 cd: directory,
                 stderr_to_stdout: true
               )
    end
  end

  defp commands(context) do
    context.state |> Path.join("commands") |> File.read!() |> String.split("\n", trim: true)
  end

  defp build(context, opts) do
    directory = Path.join(context.directory, "build")
    File.mkdir_p!(directory)

    script("otp/otp.sh", ["master", "queued-sha", "ubuntu-22.04", "amd64"], directory, [
      {"BOB_TEST_FAIL", opts[:fail] || ""} | context.env
    ])
  end

  defp script(name, args, directory, env) do
    System.cmd("bash", [Application.app_dir(:bob, "priv/scripts/#{name}") | args],
      cd: directory,
      env: env,
      stderr_to_stdout: true
    )
  end

  defp write_command(directory, name, body) do
    path = Path.join(directory, name)
    File.write!(path, "#!/bin/bash\nset -euo pipefail\n" <> body)
    File.chmod!(path, 0o755)
  end
end

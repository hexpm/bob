defmodule Bob.OTPScriptTest do
  use ExUnit.Case

  @moduletag :tmp_dir

  setup %{tmp_dir: directory} do
    bin = Path.join(directory, "bin")
    state = Path.join(directory, "docker")
    File.mkdir_p!(bin)
    File.mkdir_p!(Path.join(state, "containers"))

    write_command(bin, "docker", ~S"""
    wait_for() {
      for ((attempt=0; attempt<1000; attempt++)); do
        [ ! -f "$1" ] || return 0
        sleep 0.01
      done
      echo "Timed out waiting for $1" >&2
      exit 99
    }

    run_container() {
      [ "${BOB_TEST_FAIL:-}" != start ] || exit 42
      touch "$BOB_TEST_STATE/$BOB_TEST_JOB-started"
      if [ "${BOB_TEST_FAIL:-}" = term ]; then
        kill -TERM "$PPID"
      fi
      if [ "${BOB_TEST_OVERLAP:-}" = 1 ] && [ "$BOB_TEST_JOB" = first ]; then
        wait_for "$BOB_TEST_STATE/release-first"
      fi
      [ -f "$BOB_TEST_STATE/containers/$container" ] || exit 137
    }

    command=$1
    shift
    printf '%s %s\n' "$command" "$*" >> "$BOB_TEST_STATE/$BOB_TEST_JOB-commands"
    [ "${BOB_TEST_FAIL:-}" != "$command" ] || exit 42

    case "$command" in
      build)
        image="image-$BOB_TEST_JOB"
        while [ "$#" -gt 0 ]; do
          case "$1" in
            --iidfile) printf '%s\n' "$image" > "$2"; shift ;;
            -t) printf '%s\n' "$image" > "$BOB_TEST_STATE/tag-${2//\//_}"; shift ;;
          esac
          shift
        done
        if [ "${BOB_TEST_OVERLAP:-}" = 1 ]; then
          touch "$BOB_TEST_STATE/$BOB_TEST_JOB-built"
          if [ "$BOB_TEST_JOB" = first ]; then
            wait_for "$BOB_TEST_STATE/second-built"
          else
            wait_for "$BOB_TEST_STATE/first-started"
          fi
        fi
        ;;
      create|run)
        image=${!#}
        if [ -f "$BOB_TEST_STATE/tag-${image//\//_}" ]; then
          image=$(cat "$BOB_TEST_STATE/tag-${image//\//_}")
        fi
        container="container-$BOB_TEST_JOB"
        for arg in "$@"; do
          case "$arg" in --name=*) container=${arg#--name=} ;; esac
        done
        printf '%s\n' "$image" > "$BOB_TEST_STATE/containers/$container"
        if [ "$command" = create ]; then
          echo "$container"
        else
          run_container
        fi
        ;;
      start)
        container=${!#}
        run_container
        ;;
      cp)
        cat "$BOB_TEST_STATE/containers/${1%%:*}" > "$2"
        ;;
      rm)
        rm -f "$BOB_TEST_STATE/containers/${!#}"
        ;;
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
      {"BOB_TEST_STATE", state}
    ]

    %{directory: directory, bin: bin, state: state, env: env}
  end

  test "overlapping builds of the same branch keep their own containers and images", context do
    first = Task.async(fn -> build(context, "first", overlap: true) end)

    second_result =
      try do
        build(context, "second", overlap: true)
      after
        File.write!(Path.join(context.state, "release-first"), "")
      end

    assert {first_output, 0} = Task.await(first, 15_000)
    assert {second_output, 0} = second_result
    assert first_output =~ "Building master"
    assert second_output =~ "Building master"

    for job <- ["first", "second"] do
      assert File.read!(Path.join([context.directory, job, "master.tar.gz"])) == "image-#{job}\n"
      assert File.read!(Path.join(context.state, "#{job}-commands")) =~ "OTP_SHA=#{job}"
    end

    assert File.ls!(Path.join(context.state, "containers")) == []
  end

  for {stage, status} <- [{"start", 42}, {"cp", 42}, {"aws", 42}, {"term", 143}] do
    test "cleans up only its own container on #{stage}", context do
      File.write!(Path.join([context.state, "containers", "another-job"]), "image-other")

      assert {_output, unquote(status)} = build(context, "failed", fail: unquote(stage))
      assert File.ls!(Path.join(context.state, "containers")) == ["another-job"]
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

  defp build(context, job, opts) do
    directory = Path.join(context.directory, job)
    File.mkdir_p!(directory)

    script("otp/otp.sh", ["master", job, "ubuntu-22.04", "amd64"], directory, [
      {"BOB_TEST_JOB", job},
      {"BOB_TEST_OVERLAP", if(opts[:overlap], do: "1", else: "")},
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

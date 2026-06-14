defmodule Bob.ScriptTest do
  use ExUnit.Case

  alias Bob.Script

  describe "run/3" do
    test "script echo" do
      directory = System.tmp_dir!()
      Script.run({:script, "echo.sh"}, ["foo"], directory)

      assert File.read!(Path.join(directory, "file.txt")) == "write\n"

      assert [
               "foo\n",
               script_dir,
               "\n",
               "COMPLETED " <> _
             ] = Enum.to_list(File.stream!(Path.join(directory, "out.txt"), [], :line))

      assert String.trim(script_dir) == Application.app_dir(:bob, "priv/scripts")
    end

    @tag :timeout_binary
    test "kills a job that exceeds the timeout" do
      Application.put_env(:bob, :script_timeout, "1")
      on_exit(fn -> Application.delete_env(:bob, :script_timeout) end)

      assert_raise RuntimeError, ~r/returned: (124|137)/, fn ->
        Script.run({:cmd, "sleep 30"}, [], System.tmp_dir!())
      end
    end
  end
end

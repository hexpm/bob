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
  end
end

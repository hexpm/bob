defmodule Bob.RepoTest do
  use Bob.DataCase

  test "connects to the database" do
    assert %Postgrex.Result{rows: [[1]]} = Repo.query!("SELECT 1")
  end

  describe "init/2" do
    test "leaves opts unchanged without BOB_DATABASE_URL" do
      assert Bob.Repo.init(:supervisor, pool_size: 3) == {:ok, [pool_size: 3]}
    end

    test "applies url and pool_size from the environment without ssl when no CA cert" do
      System.put_env("BOB_DATABASE_URL", "postgres://example/bob")
      System.put_env("BOB_DATABASE_POOL_SIZE", "15")

      on_exit(fn ->
        System.delete_env("BOB_DATABASE_URL")
        System.delete_env("BOB_DATABASE_POOL_SIZE")
      end)

      {:ok, opts} = Bob.Repo.init(:supervisor, [])

      assert opts[:url] == "postgres://example/bob"
      assert opts[:pool_size] == 15
      refute Keyword.has_key?(opts, :ssl)
    end
  end
end

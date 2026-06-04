defmodule Bob.RepoTest do
  use Bob.DataCase

  test "connects to the database" do
    assert %Postgrex.Result{rows: [[1]]} = Repo.query!("SELECT 1")
  end
end

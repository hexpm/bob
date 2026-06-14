# Tests tagged :timeout_binary shell out to GNU `timeout`, which is absent on
# non-Linux dev machines; skip them there.
timeout_exclude =
  if System.find_executable("timeout") || System.find_executable("gtimeout"),
    do: [],
    else: [:timeout_binary]

ExUnit.start(exclude: timeout_exclude)
Ecto.Adapters.SQL.Sandbox.mode(Bob.Repo, :manual)

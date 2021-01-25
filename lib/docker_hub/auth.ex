defmodule Bob.DockerHub.Auth do
  use GenServer

  @timeout 24 * 60 * 60 * 1000

  def start_link([]) do
    GenServer.start_link(__MODULE__, [])
  end

  def init([]) do
    auth()
    Process.send_after(self(), :timeout, @timeout)
    {:ok, []}
  end

  def handle_info(:timeout, []) do
    auth()
    Process.send_after(self(), :timeout, @timeout)
    {:noreply, []}
  end

  defp auth() do
    username = Application.get_env(:bob, :dockerhub_username)
    password = Application.get_env(:bob, :dockerhub_password)

    if username && password do
      Bob.DockerHub.auth(username, password)
    end
  end
end

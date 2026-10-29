defmodule Bob.DockerHub.Auth do
  use GenServer

  def start_link([]) do
    GenServer.start_link(__MODULE__, [])
  end

  def init([]) do
    schedule(auth())
    {:ok, []}
  end

  def handle_info(:timeout, []) do
    schedule(auth())
    {:noreply, []}
  end

  defp auth() do
    username = Application.get_env(:bob, :dockerhub_username)
    password = Application.get_env(:bob, :dockerhub_password)

    if username && password do
      Bob.DockerHub.auth(username, password)
    end
  end

  defp schedule(nil), do: :ok
  defp schedule(token), do: Process.send_after(self(), :timeout, refresh_after(token))

  @doc """
  Milliseconds until `token` should be replaced.

  Docker Hub session tokens from an access token expire 15 minutes after they
  are issued. Logging in again after two thirds of the token's lifetime leaves
  the rest of it for the login and its retries, so requests never carry an
  expired token. The lifetime comes from the token's own `iat` and `exp`, so
  the local clock doesn't affect it.
  """
  def refresh_after(token) do
    [_header, payload, _signature] = String.split(token, ".")

    %{"iat" => issued_at, "exp" => expires_at} =
      payload |> Base.url_decode64!(padding: false) |> JSON.decode!()

    div((expires_at - issued_at) * 1000 * 2, 3)
  end
end

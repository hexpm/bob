defmodule Bob.Hexpm.Impl do
  @behaviour Bob.Hexpm

  # Token requests are not retried: authorization codes are single-use, so a
  # replay after a flaky response would be rejected by hexpm anyway.
  @impl true
  def exchange_code(code, code_verifier, redirect_uri) do
    token_request(%{
      "grant_type" => "authorization_code",
      "code" => code,
      "redirect_uri" => redirect_uri,
      "client_id" => Bob.OAuth.client_id(),
      "client_secret" => Bob.OAuth.client_secret(),
      "code_verifier" => code_verifier,
      "name" => "bob.hex.pm"
    })
  end

  @impl true
  def refresh_token(refresh_token) do
    token_request(%{
      "grant_type" => "refresh_token",
      "refresh_token" => refresh_token,
      "client_id" => Bob.OAuth.client_id(),
      "client_secret" => Bob.OAuth.client_secret()
    })
  end

  @impl true
  def revoke_token(token) do
    url = Bob.OAuth.hexpm_url() <> "/api/oauth/revoke"
    headers = [{"content-type", "application/json"}]

    body =
      JSON.encode!(%{
        "token" => token,
        "client_id" => Bob.OAuth.client_id(),
        "client_secret" => Bob.OAuth.client_secret()
      })

    case Bob.HTTP.request(:post, url, headers, body) do
      {:ok, status, _headers, _body} when status in 200..299 -> :ok
      {:ok, status, _headers, body} -> {:error, {status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def get_current_user(access_token) do
    url = Bob.OAuth.hexpm_url() <> "/api/users/me"
    headers = [{"authorization", "Bearer " <> access_token}, {"accept", "application/json"}]

    :get
    |> Bob.HTTP.request(url, headers, "")
    |> read_response()
  end

  defp token_request(body) do
    url = Bob.OAuth.hexpm_url() <> "/api/oauth/token"
    headers = [{"content-type", "application/json"}]

    :post
    |> Bob.HTTP.request(url, headers, JSON.encode!(body))
    |> read_response()
  end

  defp read_response({:ok, status, _headers, body}) when status in 200..299 do
    {:ok, JSON.decode!(body)}
  end

  defp read_response({:ok, status, _headers, body}) do
    {:error, {status, body}}
  end

  defp read_response({:error, reason}) do
    {:error, reason}
  end
end

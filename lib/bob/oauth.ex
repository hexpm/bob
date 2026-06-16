defmodule Bob.OAuth do
  @moduledoc """
  OAuth 2.0 Authorization Code with PKCE helpers for authenticating against hexpm.
  """

  def generate_code_verifier() do
    :crypto.strong_rand_bytes(32)
    |> Base.url_encode64(padding: false)
  end

  def generate_code_challenge(verifier) do
    :crypto.hash(:sha256, verifier)
    |> Base.url_encode64(padding: false)
  end

  def generate_state() do
    :crypto.strong_rand_bytes(16)
    |> Base.url_encode64(padding: false)
  end

  def authorization_url(opts) do
    state = Keyword.fetch!(opts, :state)
    code_challenge = Keyword.fetch!(opts, :code_challenge)
    redirect_uri = Keyword.fetch!(opts, :redirect_uri)

    query =
      URI.encode_query(%{
        "response_type" => "code",
        "client_id" => client_id(),
        "redirect_uri" => redirect_uri,
        "scope" => "api:read",
        "state" => state,
        "code_challenge" => code_challenge,
        "code_challenge_method" => "S256"
      })

    "#{hexpm_url()}/oauth/authorize?#{query}"
  end

  def hexpm_url(), do: Application.fetch_env!(:bob, :hexpm_url)
  def client_id(), do: Application.fetch_env!(:bob, :oauth_client_id)
  def client_secret(), do: Application.fetch_env!(:bob, :oauth_client_secret)
end

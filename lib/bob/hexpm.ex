defmodule Bob.Hexpm do
  @callback exchange_code(
              code :: String.t(),
              code_verifier :: String.t(),
              redirect_uri :: String.t()
            ) ::
              {:ok, map()} | {:error, term()}
  @callback refresh_token(refresh_token :: String.t()) :: {:ok, map()} | {:error, term()}
  @callback revoke_token(token :: String.t()) :: :ok | {:error, term()}
  @callback get_current_user(access_token :: String.t()) :: {:ok, map()} | {:error, term()}

  def exchange_code(code, code_verifier, redirect_uri) do
    impl().exchange_code(code, code_verifier, redirect_uri)
  end

  def refresh_token(refresh_token) do
    impl().refresh_token(refresh_token)
  end

  def revoke_token(token) do
    impl().revoke_token(token)
  end

  def get_current_user(access_token) do
    impl().get_current_user(access_token)
  end

  defp impl(), do: Application.fetch_env!(:bob, :hexpm_impl)
end

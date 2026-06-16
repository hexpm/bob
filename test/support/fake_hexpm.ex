defmodule Bob.FakeHexpm do
  @behaviour Bob.Hexpm

  @impl true
  def exchange_code(_code, _code_verifier, _redirect_uri), do: stubbed(:exchange_code)

  @impl true
  def refresh_token(_refresh_token), do: stubbed(:refresh_token)

  @impl true
  def revoke_token(_token), do: stubbed(:revoke_token)

  @impl true
  def get_current_user(_access_token), do: stubbed(:get_current_user)

  def stub(function, response) do
    :persistent_term.put({__MODULE__, function}, response)
  end

  def reset() do
    for {{__MODULE__, _function} = key, _value} <- :persistent_term.get() do
      :persistent_term.erase(key)
    end
  end

  defp stubbed(function) do
    :persistent_term.get({__MODULE__, function}, {:error, :not_stubbed})
  end
end

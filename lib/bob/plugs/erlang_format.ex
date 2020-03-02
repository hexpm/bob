defmodule Bob.Plug.ErlangFormat do
  def encode_to_iodata!(term) do
    :erlang.term_to_binary(term)
  end

  @spec decode(binary) :: term
  def decode("") do
    {:ok, nil}
  end

  def decode(binary) do
    term = Plug.Crypto.non_executable_binary_to_term(binary, [:safe])
    {:ok, term}
  rescue
    ArgumentError ->
      {:error, "bad binary_to_term"}
  end
end

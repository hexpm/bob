defmodule Bob.Queue.Term do
  @moduledoc """
  Ecto type for storing arbitrary Elixir terms (job keys and args) as Erlang
  external-term binaries. Preserves exact term semantics — tuples, atoms, and
  module names — which the runner applies directly. Mirrors the wire format
  used by `Bob.Plug.ErlangFormat`.
  """

  use Ecto.Type

  @impl true
  def type(), do: :binary

  @impl true
  def cast(term), do: {:ok, term}

  @impl true
  def load(binary) when is_binary(binary), do: {:ok, decode(binary)}

  @impl true
  def dump(term), do: {:ok, encode(term)}

  def encode(term), do: :erlang.term_to_binary(term, [:deterministic])

  def decode(binary), do: Plug.Crypto.non_executable_binary_to_term(binary, [:safe])

  def digest(term), do: :crypto.hash(:sha256, encode(term))
end

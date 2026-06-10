defmodule Bob.Queue.TermTest do
  use ExUnit.Case, async: true

  alias Bob.Queue.Term

  test "round-trips keys and args through encode/decode" do
    terms = [
      Bob.Job.BuildOTP,
      {Bob.Job.BuildOTP, "amd64"},
      [:tags],
      ["1.17.0", "27.0", "debian", "bookworm-20240101"],
      ["erlang", {"27.0", "alpine", "3.23"}]
    ]

    for term <- terms do
      assert term |> Term.encode() |> Term.decode() == term
    end
  end

  test "decodes atoms not yet known to this VM" do
    name = "term_test_unknown_atom_#{System.unique_integer([:positive])}"
    binary = <<131, 119, byte_size(name), name::binary>>

    assert binary |> Term.decode() |> Atom.to_string() == name
  end

  test "rejects executable terms" do
    binary = :erlang.term_to_binary(fn -> :ok end)

    assert_raise ArgumentError, fn -> Term.decode(binary) end
  end

  test "encode is deterministic regardless of map insertion order" do
    a = Map.new([{:b, 1}, {:a, 2}])
    b = Map.new([{:a, 2}, {:b, 1}])
    assert Term.encode(a) == Term.encode(b)
  end

  test "digest is stable for equal terms and differs for different terms" do
    assert Term.digest([:a]) == Term.digest([:a])
    assert Term.digest([:a]) != Term.digest([:b])
  end

  test "digest is a 32-byte sha256 binary" do
    assert byte_size(Term.digest([:a])) == 32
  end
end

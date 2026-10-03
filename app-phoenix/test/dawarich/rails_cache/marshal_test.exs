defmodule Dawarich.RailsCache.MarshalTest do
  use ExUnit.Case, async: true
  alias Dawarich.RailsCache.{Marshal, Value, Wire}

  @hash Path.expand("../../fixtures/rails_cache/codec-hash.wire", __DIR__)

  test "a Ruby hash reads as a map, or as its pairs in Ruby order when asked" do
    {:ok, %{value: map}} = Wire.decode(File.read!(@hash))
    assert map["plan"] == "pro"

    {:ok, %{value: %Value{tag: :hash_default, value: {pairs, nil}}}} =
      Wire.decode(File.read!(@hash), hash: :ordered)

    assert Enum.map(pairs, &elem(&1, 0)) == ["plan", {:ruby_symbol, "enabled"}, "limits"]
  end

  test "nesting deeper than 64 levels is refused" do
    deep = fn n -> <<4, 8>> <> String.duplicate(<<?[, 6>>, n) <> "0" end
    assert {:ok, _} = Marshal.decode(deep.(64))
    assert {:error, :too_deep} = Marshal.decode(deep.(65))
  end

  test "an object table beyond 100000 entries is refused" do
    strings = fn n -> <<4, 8, ?[, 3, n::little-24>> <> String.duplicate(<<?", 0>>, n) end
    assert {:ok, list} = Marshal.decode(strings.(99_999))
    assert length(list) == 99_999
    assert {:error, :too_large} = Marshal.decode(strings.(100_000))
  end
end

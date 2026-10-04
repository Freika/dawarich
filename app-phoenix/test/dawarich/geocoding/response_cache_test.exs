defmodule Dawarich.Geocoding.ResponseCacheTest do
  use ExUnit.Case, async: false

  alias Dawarich.Geocoding.ResponseCache
  alias Dawarich.TtlCache

  @key "https://response-cache.example.test/reverse?lat=1&lon=2"

  setup do
    keys = [@key, {ResponseCache, @key}]
    Enum.each(keys, &TtlCache.delete/1)
    on_exit(fn -> Enum.each(keys, &TtlCache.delete/1) end)
    :ok
  end

  test "a raw body is cached under its geocoder namespace" do
    body = "{\"features\":[]}\n"
    TtlCache.put(@key, :unrelated, 60_000)
    before = System.monotonic_time(:millisecond)
    ResponseCache.put(@key, body)
    after_put = System.monotonic_time(:millisecond)

    assert ResponseCache.get(@key) == {:ok, body}
    assert TtlCache.lookup(@key) == {:ok, :unrelated}

    assert [{{ResponseCache, @key}, ^body, deadline}] =
             :ets.lookup(TtlCache, {ResponseCache, @key})

    assert deadline in (before + 86_400_000)..(after_put + 86_400_000)
  end

  test "empty and nonbinary native entries are misses" do
    for value <- ["", nil, 42, %{"features" => []}] do
      TtlCache.put({ResponseCache, @key}, value, 60_000)
      assert ResponseCache.get(@key) == :error
    end

    TtlCache.put({ResponseCache, @key}, "raw bytes", 60_000)
    assert ResponseCache.get(@key) == {:ok, "raw bytes"}
  end
end

defmodule Dawarich.QrCacheTest do
  use ExUnit.Case, async: false

  alias Dawarich.{QrCache, QrSvg}

  test "fetch/2 computes a fresh key once, then serves it from the cache" do
    key = "a51b-cache-#{System.unique_integer()}"
    test = self()

    fun = fn ->
      send(test, :computed)
      "value"
    end

    assert QrCache.fetch(key, fun) == "value"
    assert_received :computed
    assert QrCache.fetch(key, fun) == "value"
    refute_received :computed
  end

  test "a full cache starts over instead of growing past 1,000 entries" do
    for n <- 1..1_001, do: QrCache.fetch("a51b-bound-#{n}", fn -> n end)

    assert :ets.info(QrCache, :size) <= 1_000
    assert QrCache.fetch("a51b-bound-1001", fn -> :recomputed end) == 1_001
  end

  test "one payload is encoded once for every module size" do
    data =
      ~s|{"server_url":"http://www.example.com/","api_key":"a51b-share-#{System.unique_integer([:positive])}"}|

    small = QrSvg.svg(data, 3)

    assert {_count, path} = QrCache.fetch(data, fn -> flunk("encoded twice") end)
    assert small =~ path
    assert QrSvg.svg(data, 6) =~ path
  end
end

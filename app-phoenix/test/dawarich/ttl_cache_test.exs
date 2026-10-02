defmodule Dawarich.TtlCacheTest do
  use ExUnit.Case, async: false

  alias Dawarich.TtlCache

  setup do
    :ets.delete_all_objects(TtlCache)
    :ok
  end

  test "fetch computes a value once and serves it until its TTL" do
    test = self()

    assert TtlCache.fetch(:places_nearby, 60_000, fn -> send(test, :computed) && :value end) ==
             :value

    assert_received :computed
    assert TtlCache.fetch(:places_nearby, 60_000, fn -> flunk("recomputed") end) == :value
  end

  test "an expired value is computed again" do
    assert TtlCache.fetch(:short, 0, fn -> :first end) == :first
    assert TtlCache.fetch(:short, 0, fn -> :second end) == :second
  end

  test "delete forgets a key" do
    assert TtlCache.fetch(:gone, 60_000, fn -> :first end) == :first
    assert TtlCache.delete(:gone) == :ok
    assert TtlCache.fetch(:gone, 60_000, fn -> :second end) == :second
  end

  test "a full table drops expired entries before it drops anything else" do
    TtlCache.fetch({:ttl, :expired}, 0, fn -> :old end)
    for n <- 1..9_999, do: TtlCache.fetch({:ttl, n}, 60_000, fn -> n end)

    TtlCache.fetch({:ttl, :new}, 60_000, fn -> :new end)

    assert :ets.info(TtlCache, :size) == 10_000
    assert TtlCache.fetch({:ttl, 1}, 60_000, fn -> flunk("evicted a live entry") end) == 1
  end

  test "the table never holds more than 10,000 entries" do
    for n <- 1..10_001, do: TtlCache.fetch({:bound, n}, 60_000, fn -> n end)

    assert :ets.info(TtlCache, :size) <= 10_000

    assert TtlCache.fetch({:bound, 10_001}, 60_000, fn -> flunk("lost the newest entry") end) ==
             10_001
  end

  test "fetch and delete follow a model over random operation sequences" do
    :rand.seed(:exsss, {ExUnit.configuration()[:seed], 303, 404})
    keys = for n <- 1..5, do: {:model, n}

    Enum.reduce(1..300, %{}, fn step, live ->
      key = Enum.random(keys)

      case :rand.uniform(3) do
        1 ->
          expected = Map.get(live, key, step)
          assert TtlCache.fetch(key, 60_000, fn -> step end) == expected
          Map.put(live, key, expected)

        2 ->
          expected = Map.get(live, key, {:short, step})
          assert TtlCache.fetch(key, 0, fn -> {:short, step} end) == expected
          live

        3 ->
          assert TtlCache.delete(key) == :ok
          Map.delete(live, key)
      end
    end)
  end
end

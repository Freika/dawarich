defmodule Dawarich.StateTest do
  use Dawarich.JobsCase, async: true, group: :scratch_db

  alias Dawarich.State

  test "a key is claimed once until its claim expires, then it can be claimed again" do
    assert State.claim(ScratchRepo, "o:jti", 60)
    refute State.claim(ScratchRepo, "o:jti", 60)
    assert State.claimed?(ScratchRepo, "o:jti")

    assert rows(
             "SELECT expires_at - statement_timestamp() BETWEEN interval '59 seconds' AND interval '60 seconds' FROM phoenix.once_claims WHERE key = 'o:jti'"
           ) == [[true]]

    [[first]] = expiry("once_claims", "o:jti")
    expire!("once_claims", "o:jti")
    refute State.claimed?(ScratchRepo, "o:jti")
    assert State.claim(ScratchRepo, "o:jti", 60)
    [[second]] = expiry("once_claims", "o:jti")
    assert DateTime.compare(second, first) == :gt
  end

  test "unclaim frees a key at once" do
    assert State.claim(ScratchRepo, "o:dedupe", 86_400)
    assert State.unclaim(ScratchRepo, "o:dedupe") == :ok
    refute State.claimed?(ScratchRepo, "o:dedupe")
    assert State.claim(ScratchRepo, "o:dedupe", 86_400)
  end

  test "claims follow a set model over random operation sequences" do
    seed!()
    keys = ~w(o:a o:b o:c o:d)

    held =
      Enum.reduce(1..200, MapSet.new(), fn _, held ->
        key = Enum.random(keys)

        case :rand.uniform(3) do
          1 ->
            assert State.claim(ScratchRepo, key, 60) == not MapSet.member?(held, key)
            MapSet.put(held, key)

          2 ->
            assert State.unclaim(ScratchRepo, key) == :ok
            MapSet.delete(held, key)

          3 ->
            expire!("once_claims", key)
            MapSet.delete(held, key)
        end
      end)

    for key <- keys, do: assert(State.claimed?(ScratchRepo, key) == MapSet.member?(held, key))
  end

  test "a counter adds within its window and starts over once the window expires" do
    assert State.increment(ScratchRepo, "c:ip:1", 1, 60) == 1
    [[window]] = expiry("counters", "c:ip:1")
    assert State.increment(ScratchRepo, "c:ip:1", 2, 60) == 3
    assert expiry("counters", "c:ip:1") == [[window]]
    expire!("counters", "c:ip:1")
    assert State.increment(ScratchRepo, "c:ip:1", 5, 60) == 5
    [[next]] = expiry("counters", "c:ip:1")
    assert DateTime.compare(next, window) == :gt
  end

  test "count reads the live value: 0 when missing or expired, and negative increments subtract" do
    assert State.count(ScratchRepo, "c:quota") == 0
    assert State.increment(ScratchRepo, "c:quota", 100, 172_800) == 100
    assert State.increment(ScratchRepo, "c:quota", -30, 172_800) == 70
    assert State.count(ScratchRepo, "c:quota") == 70
    expire!("counters", "c:quota")
    assert State.count(ScratchRepo, "c:quota") == 0
  end

  test "counters follow a running-sum model over random operation sequences" do
    seed!()
    keys = ~w(c:a c:b c:c c:d)

    model =
      Enum.reduce(1..200, %{}, fn _, model ->
        key = Enum.random(keys)

        if :rand.uniform(4) == 4 do
          expire!("counters", key)
          Map.delete(model, key)
        else
          by = :rand.uniform(11) - 6
          expected = Map.get(model, key, 0) + by
          assert State.increment(ScratchRepo, key, by, 60) == expected
          Map.put(model, key, expected)
        end
      end)

    for key <- keys, do: assert(State.count(ScratchRepo, key) == Map.get(model, key, 0))
  end

  defp seed!, do: :rand.seed(:exsss, {ExUnit.configuration()[:seed], 101, 202})

  defp expire!(table, key),
    do:
      rows(
        "UPDATE phoenix.#{table} SET expires_at = statement_timestamp() - interval '1 second' WHERE key = $1",
        [key]
      )

  defp expiry(table, key),
    do: rows("SELECT expires_at FROM phoenix.#{table} WHERE key = $1", [key])
end

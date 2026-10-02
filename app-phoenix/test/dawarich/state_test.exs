defmodule Dawarich.StateTest do
  use Dawarich.JobsCase, async: true, group: :scratch_db

  import Dawarich.LockRace

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

  test "a claim and an increment that race an open transaction on the same keys stay atomic" do
    holder =
      hold(fn ->
        true = State.claim(ScratchRepo, "o:atomic", 60)
        2 = State.increment(ScratchRepo, "c:atomic", 2, 60)
      end)

    claimer = Task.async(fn -> State.claim(ScratchRepo, "o:atomic", 60) end)
    adder = Task.async(fn -> State.increment(ScratchRepo, "c:atomic", 3, 60) end)
    wait_until(fn -> blocked("INSERT INTO phoenix.") == 2 end)
    commit(holder)

    refute Task.await(claimer)
    assert Task.await(adder) == 5
    assert State.count(ScratchRepo, "c:atomic") == 5
  end

  test "epoch_tokens seeds a missing key once and returns the same token afterwards" do
    key = "points:tile_epoch:1:2025"
    assert %{^key => token} = State.epoch_tokens(ScratchRepo, [key])
    assert token =~ ~r/\A[0-9a-f]{16}\z/
    assert State.epoch_tokens(ScratchRepo, [key]) == %{key => token}
  end

  test "bump_epochs replaces each named token once, even when repeated, and leaves other keys alone" do
    keys = ["e:1:2024", "e:1:2025", "e:1:all"]
    before = State.epoch_tokens(ScratchRepo, keys)

    assert State.bump_epochs(ScratchRepo, ["e:1:2025", "e:1:all", "e:1:all"]) == :ok

    bumped = State.epoch_tokens(ScratchRepo, keys)
    assert bumped["e:1:2024"] == before["e:1:2024"]
    refute bumped["e:1:2025"] == before["e:1:2025"]
    refute bumped["e:1:all"] == before["e:1:all"]
  end

  test "a bump inside a rolled-back transaction leaves the token as it was" do
    %{"e:2:all" => token} = State.epoch_tokens(ScratchRepo, ["e:2:all"])

    ScratchRepo.transaction(fn ->
      :ok = State.bump_epochs(ScratchRepo, ["e:2:all"])
      ScratchRepo.rollback(:domain_write_failed)
    end)

    assert State.epoch_tokens(ScratchRepo, ["e:2:all"]) == %{"e:2:all" => token}
  end

  test "two bumps naming overlapping keys in opposite orders both apply without a deadlock" do
    before = State.epoch_tokens(ScratchRepo, ["e:a", "e:b"])
    holder = hold(fn -> :ok = State.bump_epochs(ScratchRepo, ["e:a"]) end)

    forward = attempt(fn -> State.bump_epochs(ScratchRepo, ["e:a", "e:b"]) end)
    wait_until(fn -> blocked("INSERT INTO phoenix.epochs AS e") == 1 end)
    backward = attempt(fn -> State.bump_epochs(ScratchRepo, ["e:b", "e:a"]) end)
    wait_until(fn -> blocked("INSERT INTO phoenix.epochs AS e") == 2 end)
    commit(holder)

    assert Task.await(forward) == {:ok, :ok}
    assert Task.await(backward) == {:ok, :ok}
    bumped = State.epoch_tokens(ScratchRepo, ["e:a", "e:b"])
    refute bumped["e:a"] == before["e:a"]
    refute bumped["e:b"] == before["e:b"]
  end

  test "two first reads seeding overlapping keys in different orders do not wait on each other" do
    holder = hold(fn -> State.epoch_tokens(ScratchRepo, ["s:c"]) end)

    wide = attempt(fn -> State.epoch_tokens(ScratchRepo, ["s:y", "s:c", "s:x"]) end)
    wait_until(fn -> blocked("INSERT INTO phoenix.epochs (key") == 1 end)
    narrow = attempt(fn -> State.epoch_tokens(ScratchRepo, ["s:x", "s:y"]) end)
    outcome = settle(narrow, "INSERT INTO phoenix.epochs (key", 1)
    commit(holder)

    assert {:ok, %{"s:c" => _, "s:x" => x, "s:y" => y}} = Task.await(wide)
    assert {:finished, {:ok, %{"s:x" => ^x, "s:y" => ^y}}} = outcome
  end

  test "registration follows the given default until it is stored, then the stored value" do
    assert State.registration_enabled(ScratchRepo, true)
    refute State.registration_enabled(ScratchRepo, false)
    assert State.put_registration_enabled(ScratchRepo, false) == :ok
    refute State.registration_enabled(ScratchRepo, true)
    assert State.put_registration_enabled(ScratchRepo, true) == :ok
    assert State.registration_enabled(ScratchRepo, false)
    assert rows("SELECT count(*) FROM phoenix.registration_setting") == [[1]]
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

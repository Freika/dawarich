defmodule Dawarich.Tracks.PerUserLockTest do
  use ExUnit.Case, async: true, group: :scratch_db

  alias Dawarich.Redis
  alias Dawarich.Tracks.PerUserLock

  @user_id 7
  @key PerUserLock.key(@user_id)

  setup do
    url = Application.fetch_env!(:dawarich, :redis)[:url]
    start_supervised!(hd(Redis.child_specs()))
    {:ok, rails} = Redix.start_link(url, database: 1)
    {:ok, cache} = Redix.start_link(url, database: 0)
    Redix.command!(rails, ["FLUSHDB"])

    %{rails: rails, cache: cache}
  end

  test "holds the Rails key in database 1 while fun runs", %{rails: rails, cache: cache} do
    assert {:ok, :ran} =
             PerUserLock.with_user_lock(@user_id, fn ->
               assert {:ok, token} = Redix.command(rails, ["GET", @key])
               assert token =~ ~r/\A[0-9a-f-]{36}\z/

               assert {:ok, ttl} = Redix.command(rails, ["PTTL", @key])
               assert ttl in 1..60_000

               assert Redix.command(cache, ["GET", @key]) == {:ok, nil}
               :ran
             end)

    assert Redix.command(rails, ["GET", @key]) == {:ok, nil}
  end

  test "times out while another runtime holds the key", %{rails: rails} do
    Redix.command!(rails, ["SET", @key, "other", "PX", "60000"])
    parent = self()

    assert PerUserLock.with_user_lock(@user_id, fn -> send(parent, :ran) end, timeout_ms: 250) ==
             {:error, :timeout}

    refute_received :ran
    assert Redix.command(rails, ["GET", @key]) == {:ok, "other"}
  end

  test "acquires once the holder's key expires", %{rails: rails} do
    Redix.command!(rails, ["SET", @key, "other", "PX", "150"])

    assert PerUserLock.with_user_lock(@user_id, fn -> :ran end, timeout_ms: 2_000, poll_ms: 10) ==
             {:ok, :ran}
  end

  test "release never deletes another holder's token", %{rails: rails} do
    assert {:ok, :ran} =
             PerUserLock.with_user_lock(@user_id, fn ->
               Redix.command!(rails, ["SET", @key, "stolen"])
               :ran
             end)

    assert Redix.command(rails, ["GET", @key]) == {:ok, "stolen"}
  end

  test "renew extends only its own token" do
    token = Ecto.UUID.generate()
    assert {:ok, "OK"} = Redis.command(["SET", @key, token, "PX", "1000"])

    refute PerUserLock.renew(@key, "someone-else-token", 5_000)
    assert PerUserLock.renew(@key, token, 5_000)

    assert {:ok, ttl} = Redis.command(["PTTL", @key])
    assert ttl > 4_000
  end

  test "the heartbeat renews during a long body", %{rails: rails} do
    assert {:ok, :ran} =
             PerUserLock.with_user_lock(
               @user_id,
               fn ->
                 assert :ok = await_renewal(rails, @key, 400, 50)
                 assert {:ok, token} = Redix.command(rails, ["GET", @key])
                 refute is_nil(token)
                 :ran
               end,
               ttl_ms: 400,
               renew_ms: 50
             )
  end

  test "derives renew_ms from ttl_ms like Rails when the caller omits it", %{rails: rails} do
    assert {:ok, :ran} =
             PerUserLock.with_user_lock(
               @user_id,
               fn ->
                 await_elapsed(350)
                 assert {:ok, token} = Redix.command(rails, ["GET", @key])
                 refute is_nil(token)
                 :ran
               end,
               ttl_ms: 300
             )
  end

  test "a raising fun still releases", %{rails: rails} do
    assert_raise RuntimeError, fn ->
      PerUserLock.with_user_lock(@user_id, fn -> raise "boom" end)
    end

    assert Redix.command(rails, ["GET", @key]) == {:ok, nil}
  end

  test "Redis down is an error, not a crash" do
    stop_supervised!(Redix)

    assert {:error, {:redis, _}} = PerUserLock.with_user_lock(@user_id, fn -> :ran end)
  end

  defp await_renewal(conn, key, ttl_ms, renew_ms) do
    deadline = System.monotonic_time(:millisecond) + ttl_ms * 2
    await_renewal(conn, key, ttl_ms - renew_ms, false, deadline)
  end

  defp await_renewal(conn, key, threshold, decayed?, deadline) do
    if System.monotonic_time(:millisecond) >= deadline do
      flunk("PTTL never renewed above #{threshold}ms after decaying at or below it")
    else
      case Redix.command!(conn, ["PTTL", key]) do
        ttl when ttl > threshold and decayed? ->
          :ok

        ttl ->
          :erlang.yield()
          await_renewal(conn, key, threshold, decayed? or ttl <= threshold, deadline)
      end
    end
  end

  defp await_elapsed(ms) do
    deadline = System.monotonic_time(:millisecond) + ms
    wait_until(deadline)
  end

  defp wait_until(deadline) do
    if System.monotonic_time(:millisecond) >= deadline do
      :ok
    else
      :erlang.yield()
      wait_until(deadline)
    end
  end
end

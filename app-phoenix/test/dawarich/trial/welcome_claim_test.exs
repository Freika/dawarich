defmodule Dawarich.Trial.WelcomeClaimTest do
  use ExUnit.Case, async: false
  alias Dawarich.Trial.WelcomeClaim
  alias Dawarich.{Redis, RailsCache.Wire}
  @now 1_791_108_000

  setup do
    if is_nil(Process.whereis(Redis.Cache)),
      do:
        start_supervised!(
          {Redix, {System.fetch_env!("PHOENIX_TEST_REDIS_URL"), [name: Redis.Cache, database: 0]}}
        )

    keys = Enum.map(~w(floor source race), &"trial_welcome:consumed:a10b-claim-#{&1}")
    Redis.cache_command(["DEL" | keys])
    on_exit(fn -> Redis.cache_command(["DEL" | keys]) end)
    :ok
  end

  test "claims Rails welcome key once with source boolean bytes and minimum ttl" do
    assert Code.ensure_loaded?(WelcomeClaim), "welcome claim must exist"
    oracle = File.read!("test/fixtures/welcome_home/ttl_floor.json") |> Jason.decode!()
    expected = Base.decode16!(oracle["cache"]["bytes_hex"], case: :mixed)
    key = "trial_welcome:consumed:a10b-claim-floor"

    assert :claimed =
             WelcomeClaim.claim("a10b-claim-floor", @now + 10, @now, &Redis.cache_command/1)

    assert {:ok, ^expected} = Redis.cache_command(["GET", key])
    assert {:ok, ttl} = Redis.cache_command(["PTTL", key])
    assert ttl > 59_000 and ttl <= 60_000

    assert :consumed =
             WelcomeClaim.claim("a10b-claim-floor", @now + 1800, @now, &Redis.cache_command/1)

    assert {:ok, ^expected} = Redis.cache_command(["GET", key])
    source = File.read!("test/fixtures/welcome_home/valid_en.json") |> Jason.decode!()
    source_bytes = Base.decode16!(source["cache"]["bytes_hex"], case: :mixed)

    assert {:ok, "OK"} =
             Redis.cache_command([
               "SET",
               "trial_welcome:consumed:a10b-claim-source",
               source_bytes,
               "PX",
               60_000
             ])

    assert :consumed =
             WelcomeClaim.claim("a10b-claim-source", @now + 1800, @now, &Redis.cache_command/1)

    assert {:ok, %{value: true, expires_at: expires}} = Wire.decode(expected)
    assert expires == @now + 60
    parent = self()

    capture = fn args ->
      send(parent, {:command, args})
      {:ok, "OK"}
    end

    assert :claimed = WelcomeClaim.claim("bounded-jti", @now + 1800.9, @now, capture)

    assert_receive {:command,
                    ["SET", "trial_welcome:consumed:bounded-jti", bytes, "NX", "PX", "1800000"]}

    assert {:ok, %{value: true, expires_at: expires}} = Wire.decode(bytes)
    assert expires == @now + 1800

    assert {:error, :unsupported_key} =
             WelcomeClaim.claim(String.duplicate("x", 1024), @now + 10, @now, capture)

    refute_receive {:command, _}
  end

  test "two real Redis contenders permit exactly one claim and preserve errors" do
    assert Code.ensure_loaded?(WelcomeClaim), "welcome claim must exist"
    command = &Redis.cache_command/1

    contenders =
      for _ <- 1..2,
          do:
            Task.async(fn ->
              WelcomeClaim.claim("a10b-claim-race", @now + 1800, @now, command)
            end)

    assert contenders |> Enum.map(&Task.await/1) |> Enum.sort() == [:claimed, :consumed]

    assert {:error, :synthetic_redis_failure} =
             WelcomeClaim.claim("a10b-claim-race", @now + 1800, @now, fn _ ->
               {:error, :synthetic_redis_failure}
             end)

    assert {:error, _} =
             WelcomeClaim.claim("a10b-claim-race", @now + 1800, @now, fn _ ->
               Redis.cache_command(["SET", "trial_welcome:consumed:a10b-claim-race"])
             end)

    assert :consumed = WelcomeClaim.claim("a10b-claim-race", @now + 1800, @now, command)
  end
end

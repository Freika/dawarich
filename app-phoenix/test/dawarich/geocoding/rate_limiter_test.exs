defmodule Dawarich.Geocoding.RateLimiterTest do
  use ExUnit.Case, async: false

  alias Dawarich.Geocoding.{Providers, RateLimiter}
  alias Dawarich.Redis

  setup do
    start_supervised!(hd(Redis.child_specs()))
    :ok
  end

  test "the Lua is Rails' Lua" do
    assert rails_lua() == RateLimiter.lua()
  end

  test "consecutive reservations are spaced by the interval" do
    key = "wave5b_rl_spacing"
    Redis.command(["DEL", key])

    lua =
      """
      local server_redis = redis
      local redis = {call = function(command, ...)
        if command == 'TIME' then return {'1000', '0'} end
        return server_redis.call(command, ...)
      end}
      local reserve = function()
      """ <> RateLimiter.lua() <> "\nend\nreturn {reserve(), reserve(), reserve()}"

    assert Redis.command(["EVAL", lua, "1", key, "100000", "-1"]) ==
             {:ok, [0, 100_000, 200_000]}
  end

  test "idle time banks nothing" do
    key = "wave5b_rl_idle"
    Redis.command(["SET", key, "1"])

    assert reserve(key, 10) == 0
  end

  test "Rails' reservation and Phoenix's share one bucket" do
    key = "geocoding:rate_limit:photon:photon.komoot.io"
    Redis.command(["DEL", key])

    url = Application.fetch_env!(:dawarich, :redis)[:url]
    {:ok, rails} = Redix.start_link(url, database: 1)
    assert {:ok, 0} = Redix.command(rails, ["EVAL", RateLimiter.lua(), "1", key, "1000000", "-1"])

    config = %{rps: 1, provider: :photon, host: "photon.komoot.io", api_key: nil}
    {elapsed, :ran} = :timer.tc(fn -> RateLimiter.throttle(config, fn -> :ran end) end)

    assert elapsed >= 900_000
  end

  test "nil or non-positive rps never calls Redis" do
    stop_supervised!(Redix)
    function = {Redis, :command, 3}
    :erlang.trace_pattern(function, true, [:call_count])
    on_exit(fn -> :erlang.trace_pattern(function, false, [:call_count]) end)

    for rps <- [nil, 0, -1] do
      assert RateLimiter.throttle(%{rps: rps}, fn -> :ran end) == :ran
    end

    assert {:call_count, 0} = :erlang.trace_info(function, :call_count)
  end

  test "Redis down waits one interval and runs" do
    stop_supervised!(Redix)
    config = %{rps: 20, provider: :photon, host: "unreachable.test", api_key: nil}

    {elapsed, :ran} = :timer.tc(fn -> RateLimiter.throttle(config, fn -> :ran end) end)

    assert elapsed >= 50_000
  end

  test "bucket keys" do
    komoot = %{provider: :photon, host: "photon.komoot.io", api_key: nil}
    assert RateLimiter.key(komoot) == "photon:photon.komoot.io"

    geoapify = %{provider: :geoapify, host: nil, api_key: "k"}
    assert RateLimiter.key(geoapify) == "geoapify:" <> Providers.key_digest(geoapify)

    chibigeo = %{provider: :photon, host: "app.chibigeo.com/v1/photon", api_key: "k"}

    assert RateLimiter.key(chibigeo) ==
             "photon:app.chibigeo.com:" <> Providers.key_digest(chibigeo)

    self_hosted = %{provider: :photon, host: "self-hosted.example", api_key: "k"}
    assert RateLimiter.key(self_hosted) == "photon:self-hosted.example"
  end

  defp reserve(key, rps) do
    interval = round(1_000_000 / rps)

    {:ok, wait} =
      Redis.command(["EVAL", RateLimiter.lua(), "1", key, Integer.to_string(interval), "-1"])

    wait
  end

  defp rails_lua do
    path = Path.expand("../../../../app/services/geocoding/rate_limiter.rb", __DIR__)
    [_, body] = Regex.run(~r/RESERVE_LUA = <<~LUA\n(.*?)\n[ \t]*LUA\n/s, File.read!(path))

    lines = String.split(body, "\n")

    indent =
      lines
      |> Enum.filter(&(String.trim(&1) != ""))
      |> Enum.map(&(byte_size(&1) - byte_size(String.trim_leading(&1))))
      |> Enum.min()

    lines
    |> Enum.map(&String.slice(&1, indent, byte_size(&1) - indent))
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end
end

defmodule Dawarich.Places.NearbyTest.Http do
  use Agent

  def start_link(_), do: Agent.start_link(fn -> {[], []} end, name: __MODULE__)
  def respond(features), do: Agent.update(__MODULE__, fn {_, calls} -> {features, calls} end)
  def calls, do: Agent.get(__MODULE__, fn {_, calls} -> Enum.reverse(calls) end)

  def request(_url, _headers) do
    features =
      Agent.get_and_update(__MODULE__, fn {features, calls} ->
        {features, {features, [System.monotonic_time(:microsecond) | calls]}}
      end)

    {:ok, 200, Jason.encode!(%{"type" => "FeatureCollection", "features" => features})}
  end
end

defmodule Dawarich.Places.NearbyTest do
  use ExUnit.Case, async: false

  alias Dawarich.Geocoding.{RateLimiter, ResponseCache}
  alias Dawarich.Places.Nearby
  alias Dawarich.Places.NearbyTest.Http
  alias Dawarich.{Redis, TtlCache}

  setup do
    start_supervised!(Http)
    start_supervised!(hd(Redis.child_specs()))
    previous = Application.fetch_env!(:dawarich, :geocoding_http)
    Application.put_env(:dawarich, :geocoding_http, Http)

    on_exit(fn ->
      Application.put_env(:dawarich, :geocoding_http, previous)
      :ets.match_delete(TtlCache, {{ResponseCache, :_}, :_, :_})
    end)

    :ok
  end

  @tag nearby_limiter_fallback: true
  test "Redis limiter errors pace nearby calls locally and retain the interactive wait bound" do
    config = config("fallback-nearby.example.test", 0.25)
    Http.respond([feature(%{"name" => "Synthetic Place"})])
    stop_supervised!(Redix)

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        assert [_] = Nearby.fetch(nil, 51.0, 12.0, 0.5, 5, config: config)

        tasks =
          for lat <- [52.0, 53.0, 54.0],
              do: Task.async(fn -> Nearby.fetch(nil, lat, 12.0, 0.5, 5, config: config) end)

        assert Enum.map(tasks, &Task.await/1) == [[], [], []]
        assert length(Http.calls()) == 1

        paced = config("paced-nearby.example.test", 20)
        assert [_] = Nearby.fetch(nil, 51.0, 12.0, 0.5, 5, config: paced)

        tasks =
          for lat <- [52.0, 53.0, 54.0],
              do: Task.async(fn -> Nearby.fetch(nil, lat, 12.0, 0.5, 5, config: paced) end)

        assert Enum.all?(Enum.map(tasks, &Task.await/1), &(length(&1) == 1))
        [_ | starts] = Http.calls()
        assert Enum.all?(Enum.zip(starts, tl(starts)), fn {a, b} -> b - a >= 49_000 end)
      end)

    assert log =~ "event=geocoding.rate_limiter_unavailable"
    refute log =~ config.host
    refute log =~ config.api_key

    start_supervised!(hd(Redis.child_specs()))
    key = "geocoding:rate_limit:" <> RateLimiter.key(config)
    assert {:ok, _} = Redis.command(["DEL", key])
    on_exit(fn -> Redis.command(["DEL", key]) end)
    assert [_] = Nearby.fetch(nil, 55.0, 12.0, 0.5, 5, config: config)
    assert [] = Nearby.fetch(nil, 56.0, 12.0, 0.5, 5, config: config)
    assert length(Http.calls()) == 6
  end

  defp config(host, rps),
    do: %{
      enabled: true,
      source: :stored,
      provider: :photon,
      host: host,
      api_key: "synthetic-nearby-key",
      use_https: false,
      rps: rps
    }

  defp feature(properties),
    do: %{
      "type" => "Feature",
      "geometry" => %{"type" => "Point", "coordinates" => [12.0, 51.0]},
      "properties" => properties
    }
end

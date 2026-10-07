defmodule Dawarich.Places.NearbyTest.Http do
  use Agent

  def start_link(_), do: Agent.start_link(fn -> {[], []} end, name: __MODULE__)
  def respond(features), do: Agent.update(__MODULE__, fn {_, calls} -> {features, calls} end)
  def calls, do: Agent.get(__MODULE__, fn {_, calls} -> Enum.reverse(calls) end)

  def request(url, _headers) do
    features =
      Agent.get_and_update(__MODULE__, fn {features, calls} ->
        {features, {features, [url | calls]}}
      end)

    {:ok, 200, Jason.encode!(%{"type" => "FeatureCollection", "features" => features})}
  end
end

defmodule Dawarich.Places.NearbyTest do
  use ExUnit.Case, async: false
  import Phoenix.LiveViewTest, only: [render_component: 2]

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

        bucket = RateLimiter.key(paced)
        next_slot = Map.fetch!(:sys.get_state(RateLimiter), bucket)

        tasks =
          for lat <- [52.0, 53.0, 54.0],
              do: Task.async(fn -> Nearby.fetch(nil, lat, 12.0, 0.5, 5, config: paced) end)

        assert Enum.all?(Enum.map(tasks, &Task.await/1), &(length(&1) == 1))
        assert length(Http.calls()) == 5
        assert Map.fetch!(:sys.get_state(RateLimiter), bucket) >= next_slot + 150_000
      end)

    assert log =~ "event=geocoding.rate_limiter_unavailable"
    refute log =~ config.host
    refute log =~ config.api_key

    start_supervised!(hd(Redis.child_specs()))
    config = config("healthy-nearby.example.test", 0.25)
    key = "geocoding:rate_limit:" <> RateLimiter.key(config)
    assert {:ok, _} = Redis.command(["DEL", key])
    on_exit(fn -> Redis.command(["DEL", key]) end)
    assert [_] = Nearby.fetch(nil, 55.0, 12.0, 0.5, 5, config: config)
    assert [] = Nearby.fetch(nil, 56.0, 12.0, 0.5, 5, config: config)
    assert length(Http.calls()) == 6
  end

  @tag nearby_name_fallback: true
  test "blank nearby provider names use exactly Rails address city and unknown fallbacks" do
    config = config("names-nearby.example.test", nil)

    cases = [
      {%{"name" => "", "street" => "Example Street", "housenumber" => "7"}, "Example Street 7"},
      {%{"name" => " \t\n", "street" => "Example Street"}, "Example Street"},
      {%{"name" => nil, "street" => " ", "city" => "Leipzig"}, "Leipzig"},
      {%{"name" => "", "city" => "Leipzig"}, "Leipzig"},
      {%{"name" => ""}, "Unknown Place"},
      {%{"name" => "", "city" => ""}, ""},
      {%{"name" => "Venue", "street" => "Example Street"}, "Venue"}
    ]

    Http.respond(Enum.map(cases, fn {props, _} -> feature(props) end))
    places = Nearby.fetch(nil, 51.0, 12.0, 0.5, 10, config: config)
    assert Enum.map(places, & &1["name"]) == Enum.map(cases, &elem(&1, 1))
    assert Enum.map(places, & &1["geodata"]) == Enum.map(cases, fn {p, _} -> feature(p) end)

    html =
      render_component(&DawarichWeb.NearbyPlaces.render/1,
        places: Enum.take(places, 1),
        radius: 1.5,
        params: %{},
        locale: "en"
      )

    assert html =~ ~s(data-place-name="Example Street 7")
    assert html =~ ~s(<h4 class="font-semibold">Example Street 7</h4>)
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

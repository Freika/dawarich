defmodule Dawarich.Geocoding.QueryTest do
  use ExUnit.Case, async: true

  import Dawarich.GeocodingCase, only: [config_from: 1, fixture_names: 0]

  alias Dawarich.Geocoding.{Query, RateLimiter}
  alias Dawarich.Wave5bFixtures

  @version "9.9.9"
  @place_opts [limit: 10, distance_sort: true, radius: 1]
  @ignored ~w(user-agent accept-encoding)

  test "URLs, cache keys and headers match Rails for every recorded request" do
    scenarios =
      Enum.flat_map(
        fixture_names(),
        &scenarios(Path.basename(&1, ".json"), Wave5bFixtures.read!(&1))
      )

    assert length(scenarios) > 20

    for {name, config, queries, requests, cache} <- scenarios do
      built =
        Enum.map(queries, fn {coords, opts} -> Query.build(config, coords, opts, @version) end)

      by_url = Map.new(built, fn {url, key, headers} -> {url, {key, headers}} end)

      assert {name, Enum.sort(Map.keys(by_url))} ==
               {name, requests |> Enum.map(& &1["url"]) |> Enum.uniq() |> Enum.sort()}

      for request <- requests do
        {_key, headers} = by_url[request["url"]]
        assert {name, comparable(headers)} == {name, comparable(request["headers"])}
        assert {"user-agent", "Dawarich #{@version} (https://dawarich.app)"} in headers
      end

      ok_keys =
        for request <- requests,
            request["status"] in 200..399,
            uniq: true,
            do: elem(by_url[request["url"]], 0)

      assert {name, Enum.sort(ok_keys)} == {name, cache |> Enum.map(& &1["key"]) |> Enum.sort()}
    end
  end

  test "the limiter bucket of a recorded fixture is Rails'" do
    f = Wave5bFixtures.read!("test/fixtures/geocoding/photon_chibigeo.json")
    assert RateLimiter.key(config_from(f["config"])) == f["rate_limit"]["key"]
  end

  test "x-api-key goes only to Photon with a key" do
    base = %{
      enabled: true,
      source: :stored,
      host: "h.example.test",
      use_https: true,
      rps: nil,
      store_geodata: true
    }

    headers = fn config ->
      config |> Query.build({1.0, 2.0}, [], @version) |> elem(2) |> Map.new()
    end

    assert headers.(Map.merge(base, %{provider: :photon, api_key: "k"}))["x-api-key"] == "k"
    refute Map.has_key?(headers.(Map.merge(base, %{provider: :photon, api_key: ""})), "x-api-key")

    refute Map.has_key?(
             headers.(Map.merge(base, %{provider: :nominatim, api_key: "k"})),
             "x-api-key"
           )

    refute Map.has_key?(
             headers.(Map.merge(base, %{provider: :geoapify, api_key: "k"})),
             "x-api-key"
           )
  end

  defp scenarios(_name, %{"cases" => cases}) do
    for %{"query" => [lat, lon], "requests" => [_ | _] = requests} = c <- cases,
        do: {c["name"], config_from(c["config"]), [{{lat, lon}, []}], requests, c["cache"]}
  end

  defp scenarios(name, %{"place_id" => id, "input" => input} = f) do
    place = Enum.find(input["places"], &(&1["id"] == id))

    [
      {name, config_from(f["config"]), [{coords(place["lonlat_wkt"]), @place_opts}],
       f["requests"], f["cache"]}
    ]
  end

  defp scenarios(
         name,
         %{"calls" => _, "config" => %{"enabled" => true} = config, "input" => input} = f
       ) do
    queries = for point <- input["points"], do: {coords(point["lonlat_wkt"]), []}
    [{name, config_from(config), queries, f["requests"], f["cache"]}]
  end

  defp scenarios(_name, _fixture), do: []

  defp coords(wkt) do
    [lon, lat] = Regex.run(~r/POINT\((\S+) (\S+)\)/, wkt, capture: :all_but_first)
    {elem(Float.parse(lat), 0), elem(Float.parse(lon), 0)}
  end

  defp comparable(headers) do
    for {name, value} <- headers,
        name = String.downcase(name),
        name not in @ignored,
        into: %{},
        do: {name, value}
  end
end

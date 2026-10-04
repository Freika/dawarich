defmodule Dawarich.Geocoding.PlaceFetchTest do
  use Dawarich.GeocodingCase, async: false

  alias Dawarich.Geocoding.{Config, PlaceFetch}

  @fixtures ~w(place_siblings place_name_locked place_privacy_mode place_lonlat_from_decimals
               place_name_too_long place_without_coordinates)
  @columns ~w(id user_id name latitude longitude lonlat_wkt city country source import_id demo note geodata
              name_locked_at reverse_geocoded_at)
  @place_sql "SELECT id, user_id, name, latitude::text, longitude::text, ST_AsText(lonlat), city, country, " <>
               "source, import_id, demo, note, geodata::text, name_locked_at IS NOT NULL, " <>
               "reverse_geocoded_at IS NOT NULL FROM places WHERE user_id = $1 ORDER BY id"

  for name <- @fixtures do
    @name name

    test "every place fixture ends with Rails' places, text for text: #{name}" do
      f = load!(@name)
      stub_requests!(f["requests"])
      config = Config.resolve(ScratchRepo, %{})
      assert comparable(config) == f["config"]

      if f["expected"]["raised"],
        do:
          assert_raise(ArgumentError, fn -> PlaceFetch.run(ScratchRepo, f["place_id"], config) end),
        else: assert(PlaceFetch.run(ScratchRepo, f["place_id"], config) == :ok)

      assert places(f) == expected_places(f)
      assert FakeHttp.requests() == Enum.map(f["requests"], & &1["url"])
      assert cache_entries() == Enum.sort_by(f["cache"], & &1["key"])
    end
  end

  test "the queried place's lonlat comes from its decimals" do
    f = load!("place_lonlat_from_decimals")
    stub_requests!(f["requests"])
    [%{"lonlat_wkt" => "POINT(12.374 51.34)"}] = f["input"]["places"]

    assert PlaceFetch.run(ScratchRepo, f["place_id"], Config.resolve(ScratchRepo, %{})) == :ok
    assert [[_, _, _, "51.339700", "12.373100", "POINT(12.3731 51.3397)" | _]] = places(f)
  end

  test "geodata floats from the provider are stored as Rails stores them" do
    f = load!("place_siblings")
    [%{"url" => url, "status" => status, "body" => body}] = f["requests"]
    FakeHttp.stub(url, status, with_rails_rounding_cases(body))

    assert PlaceFetch.run(ScratchRepo, f["place_id"], Config.resolve(ScratchRepo, %{})) == :ok

    [user] = f["input"]["users"]

    assert ScratchRepo.query!(
             "SELECT geodata->'properties'->>'extent', geodata->'properties'->>'distance' " <>
               "FROM places WHERE user_id = $1 ORDER BY id",
             [user["id"]]
           ).rows == List.duplicate(["[12.3731, 51.3398, 12.3732, 51.3397]", "1500.0"], 4)
  end

  test "name over 255 and missing coordinates raise" do
    for name <- ~w(place_name_too_long place_without_coordinates) do
      Dawarich.FixtureCleanup.delete!(ScratchRepo, ~w(places  instance_settings))

      clear_response_cache!()
      f = load!(name)
      stub_requests!(f["requests"])
      before = places(f)

      assert_raise ArgumentError, fn ->
        PlaceFetch.run(ScratchRepo, f["place_id"], Config.resolve(ScratchRepo, %{}))
      end

      assert places(f) == before
    end
  end

  test "a missing place, a disabled configuration and a failed lookup write nothing" do
    f = load!("place_siblings")
    before = places(f)
    config = Config.resolve(ScratchRepo, %{})

    ExUnit.CaptureLog.capture_log(fn ->
      assert PlaceFetch.run(ScratchRepo, 424_242, config) == :missing

      assert PlaceFetch.run(ScratchRepo, f["place_id"], %{enabled: false, store_geodata: true}) ==
               :ok

      FakeHttp.stub(hd(f["requests"])["url"], 429, "slow down")
      assert PlaceFetch.run(ScratchRepo, f["place_id"], config) == :ok
    end)

    assert places(f) == before
  end

  defp places(f) do
    [user] = f["input"]["users"]
    ScratchRepo.query!(@place_sql, [user["id"]], log: false).rows
  end

  defp expected_places(f) do
    for place <- f["expected"]["places"] do
      Enum.map(@columns, fn
        column when column in ~w(name_locked_at reverse_geocoded_at) -> place[column] != nil
        column -> place[column]
      end)
    end
  end
end

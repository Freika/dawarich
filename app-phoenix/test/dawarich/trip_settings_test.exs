defmodule Dawarich.TripSettingsTest do
  use ExUnit.Case, async: true

  alias Dawarich.TripSettings

  test "Rails' defaults: km, light, 500 m, 30 min, no AirTrail, no photos" do
    for settings <- [nil, %{}],
        do:
          assert(
            TripSettings.read(settings) ==
              {:ok,
               %{
                 unit: "km",
                 factor: 1000,
                 style: "light",
                 meters: 500,
                 minutes: 30,
                 airtrail: false,
                 photos: false
               }}
          )
  end

  test "strings and floats are read with Ruby's to_i; non-positive values fall back; minutes are capped" do
    assert {:ok, %{meters: 750, minutes: 90}} =
             TripSettings.read(%{
               "meters_between_routes" => "750abc",
               "minutes_between_routes" => 90.9
             })

    assert {:ok, %{meters: 500, minutes: 30}} =
             TripSettings.read(%{"meters_between_routes" => "0", "minutes_between_routes" => -5})

    assert {:ok, %{minutes: 1440}} = TripSettings.read(%{"minutes_between_routes" => "5000"})
  end

  test "the unit comes from maps.distance_unit, the style from maps_maplibre_style" do
    assert {:ok, %{unit: "mi", factor: 1609.34, style: "dark"}} =
             TripSettings.read(%{
               "maps" => %{"distance_unit" => "mi"},
               "maps_maplibre_style" => "dark"
             })

    assert {:ok, %{unit: "km", style: "light"}} =
             TripSettings.read(%{
               "maps" => %{"distance_unit" => nil},
               "maps_maplibre_style" => false
             })
  end

  test "AirTrail needs a present URL; photos need a present URL and key of one integration" do
    assert {:ok, %{airtrail: false}} = TripSettings.read(%{"airtrail_url" => "  "})

    assert {:ok, %{airtrail: true}} =
             TripSettings.read(%{"airtrail_url" => "https://airtrail.example"})

    assert {:ok, %{photos: false}} =
             TripSettings.read(%{
               "immich_url" => "https://immich.example",
               "immich_api_key" => " "
             })

    assert {:ok, %{photos: true}} =
             TripSettings.read(%{
               "photoprism_url" => "https://photos.example",
               "photoprism_api_key" => "fixture"
             })
  end

  test "values Rails would raise on hand the page back" do
    for settings <- [
          %{"maps" => "km"},
          %{"maps" => %{"distance_unit" => "KM"}},
          %{"maps_maplibre_style" => 3},
          %{"meters_between_routes" => true},
          %{"minutes_between_routes" => %{}}
        ] do
      assert TripSettings.read(settings) == :rails, inspect(settings)
    end
  end

  test "a timezone that is not a string hands the page back; a string or none does not" do
    assert TripSettings.read(%{"timezone" => 5}) == :rails
    assert TripSettings.read(%{"timezone" => ["Europe/Berlin"]}) == :rails
    assert {:ok, _} = TripSettings.read(%{"timezone" => "Berlin"})
    assert {:ok, _} = TripSettings.read(%{"timezone" => nil})
  end

  test "a present zone must resolve to itself; a blank or missing zone falls back as in Rails" do
    assert TripSettings.zone?(%{"timezone" => "Berlin"}, "Europe/Berlin")
    assert TripSettings.zone?(%{"timezone" => "UTC"}, "Etc/UTC")
    refute TripSettings.zone?(%{"timezone" => "Europe/Atlantis"}, "Europe/Berlin")
    assert TripSettings.zone?(%{"timezone" => "  "}, "Europe/Berlin")
    assert TripSettings.zone?(%{}, "Etc/UTC")
  end
end

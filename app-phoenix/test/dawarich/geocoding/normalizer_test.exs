defmodule Dawarich.Geocoding.NormalizerTest do
  use ExUnit.Case, async: true

  import Dawarich.GeocodingCase, only: [fixture_names: 0]

  alias Dawarich.Geocoding.Normalizer
  alias Dawarich.Wave5bFixtures

  test "from_data and the place normalization equal Rails for every recorded result" do
    results =
      for path <- fixture_names(),
          result <- Wave5bFixtures.read!(path)["results"] || [],
          do: {Path.basename(path, ".json"), result}

    assert length(results) > 20

    for {name, %{"data" => data, "normalized" => normalized, "place_normalized" => place}} <-
          results do
      %{properties: properties, coords: coords} = Normalizer.from_data(data)
      assert {name, %{"properties" => properties, "coords" => coords}} == {name, normalized}
      assert {name, Normalizer.place(data)} == {name, place}
    end
  end

  test "flat results follow Rails' key precedence" do
    data = %{
      "display_name" => ",, Leipzig",
      "lat" => "51.3397",
      "lon" => "12.3731",
      "type" => "cafe",
      "class" => "amenity",
      "address" => %{
        "cafe" => "7",
        "house_number" => "7",
        "footway" => "Weg",
        "municipality" => "Leipzig"
      }
    }

    %{properties: p, coords: coords} = Normalizer.from_data(data)
    assert coords == [12.3731, 51.3397]
    assert p["address_name"] == nil
    assert p["street"] == "Weg"
    assert p["city"] == "Leipzig"
    assert p["osm_key"] == "amenity"
    assert p["osm_value"] == "cafe"

    assert Normalizer.from_data(%{"display_name" => ",,,", "lat" => "1"}).properties[
             "address_name"
           ] == nil

    assert Normalizer.from_data(%{"display_name" => " A , B"}).properties["address_name"] == "A"
    assert Normalizer.from_data([1]) == %{properties: %{}, coords: nil}
    assert Normalizer.from_data(%{"x" => 1}) == %{properties: %{}, coords: nil}
  end

  test "a FeatureCollection unwraps to its first feature and Geoapify falls back to properties" do
    feature = %{
      "properties" => %{
        "name" => " ",
        "lon" => "12.5",
        "lat" => 51,
        "datasource" => %{"osm_id" => 9}
      }
    }

    %{properties: p, coords: coords} = Normalizer.from_data(%{"features" => [feature]})
    assert coords == [12.5, 51.0]
    assert p["name"] == nil
    assert p["osm_id"] == 9
  end
end

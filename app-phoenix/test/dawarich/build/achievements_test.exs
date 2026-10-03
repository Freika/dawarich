defmodule Dawarich.Build.AchievementsTest do
  use ExUnit.Case, async: true

  alias Dawarich.Build.Achievements

  @moduletag :tmp_dir

  @planet """
  continents:
    Europe:
      countries:
        DE:
          name: Germany
          art: {lat: 51.0, lon: 10.0, zoom: 4.0}
          subdivisions:
            DE-SN: Saxony
            DE-BE: Berlin
        LU:
          name: Luxembourg
          art: {lat: 49.6, lon: 6.1, zoom: 8.0}
          subdivisions: {}
    Antarctica:
      countries:
        AQ:
          name: Antarctica
          art: {lat: -80.0, lon: 0.0, zoom: 1.0}
          subdivisions: {}
  """

  @hand """
  _continents:
    Europe:
      flavor: x
      child_zoom: 3.2
  border_hopper:
    kind: region_set
    name: Border Hopper
    threshold: 2
  """

  @translations %{
    "en" => %{"achievements" => %{"cards" => %{"explorer_name" => "%{place} Explorer"}}},
    "de" => %{"achievements" => %{"cards" => %{"explorer_name" => "%{place}-Entdecker"}}}
  }

  setup %{tmp_dir: root} do
    File.mkdir_p!(Path.join(root, "config/achievements"))
    File.write!(Path.join(root, "config/achievements/planet.yml"), @planet)
    File.write!(Path.join(root, "config/achievements.yml"), @hand)
    :ok
  end

  test "builds hand, continent and country sets in Rails order with the rake task's fields", %{
    tmp_dir: root
  } do
    json = root |> Achievements.export(@translations) |> IO.iodata_to_binary()
    ordered = Jason.decode!(json, objects: :ordered_objects)["definitions"]
    definitions = Jason.decode!(json)["definitions"]
    by_key = Map.new(definitions, &{&1["key"], &1})

    assert Enum.map(definitions, & &1["key"]) ==
             ~w(border_hopper continent_europe country_de country_lu country_aq)

    assert Enum.map(hd(ordered).values, &elem(&1, 0)) ==
             ~w(key kind level flat threshold total target regions region_codes names)

    assert %{"total" => 3, "target" => 2, "region_codes" => ["DE", "LU", "AQ"]} =
             by_key["border_hopper"]

    assert by_key["border_hopper"]["names"] |> Map.values() |> Enum.uniq() == ["Border Hopper"]

    assert %{"flat" => false, "threshold" => nil, "target" => 2} = by_key["continent_europe"]
    assert by_key["continent_europe"]["names"]["de"] == "Europe-Entdecker"
    assert by_key["continent_europe"]["names"]["fr"] == "Europe Explorer"

    assert %{"level" => "subdivision", "region_codes" => ["DE-SN", "DE-BE"]} =
             by_key["country_de"]

    assert %{"level" => "country", "flat" => true, "regions" => %{"LU" => "Luxembourg"}} =
             by_key["country_lu"]

    assert by_key["country_lu"]["names"]["de"] == "Luxembourg"

    assert Map.keys(by_key["country_aq"]["names"]) |> Enum.sort() ==
             Enum.sort(~w(en de es fr pl ca zh))
  end
end

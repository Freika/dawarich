defmodule Dawarich.Achievements.RegistryTest do
  use ExUnit.Case, async: true

  alias Dawarich.Achievements.Registry

  test "loads the exported registry in Rails order" do
    assert Registry.all() |> Enum.take(3) |> Enum.map(& &1.key) ==
             ~w(border_hopper globetrotter world_traveler)

    assert Registry.find("country_de").level == "subdivision"
    assert Registry.announcer("DE-SN").key == "country_de"
    assert Registry.announcer("LU").key == "continent_europe"
  end

  test "geography visibility follows Rails' rule" do
    assert Registry.visible_geography?("DE")
    assert Registry.visible_geography?("DE-SN")
    assert Registry.visible_geography?("LU")
    refute Registry.visible_geography?("XX")
    refute Registry.visible_geography?("ZZ-99")
  end

  test "definitions carry the card, geography and name the achievement pages render" do
    assert %{
             name: "Germany Explorer",
             country: "DE",
             continent: "Europe",
             parent_key: "continent_europe",
             card: %{"place" => "Germany", "rarity" => "Rare", "art" => %{"zoom" => 4.3}}
           } = Registry.find("country_de")

    assert %{country: nil, parent_key: nil, card: %{"rarity" => "Legendary"}} =
             Registry.find("continent_europe")
  end

  test "transliteration follows the exported I18n table" do
    assert Registry.approximations("de")["ß"] == "ss"
    assert Registry.approximations("zh")["Ł"] == "L"
    refute Map.has_key?(Registry.approximations("en"), "中")
  end

  test "every exported definition carries a name in each available locale" do
    for d <- Registry.all(),
        l <- Dawarich.I18n.available_locales(),
        do: assert(is_binary(d.names[l]))
  end
end

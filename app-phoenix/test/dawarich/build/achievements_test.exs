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
    File.mkdir_p!(Path.join(root, "config/locales"))
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
             ~w(key kind level flat threshold total target regions region_codes names name country continent parent_key card)

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

  test "exports complete hand, continent, gridded and flat country metadata", %{tmp_dir: root} do
    definitions =
      root |> Achievements.export(@translations) |> IO.iodata_to_binary() |> Jason.decode!()

    by_key = Map.new(definitions["definitions"], &{&1["key"], &1})

    assert %{
             "name" => "Border Hopper",
             "country" => nil,
             "continent" => nil,
             "parent_key" => nil,
             "card" => %{}
           } = by_key["border_hopper"]

    assert %{
             "name" => "Europe Explorer",
             "country" => nil,
             "continent" => "Europe",
             "parent_key" => nil,
             "card" => %{
               "rarity" => "Legendary",
               "description" => "Spend time in all 2 countries and territories of Europe.",
               "flavor" => "x",
               "place" => "Europe",
               "child_zoom" => 3.2,
               "art" => nil
             }
           } = by_key["continent_europe"]

    assert %{
             "name" => "Germany Explorer",
             "country" => "DE",
             "continent" => "Europe",
             "parent_key" => "continent_europe",
             "card" => %{
               "rarity" => "Rare",
               "description" => "Spend time in all 2 regions of Germany.",
               "place" => "Germany",
               "child_zoom" => 5.5,
               "art" => %{"lat" => 51.0, "lon" => 10.0, "zoom" => 4.0}
             }
           } = by_key["country_de"]

    assert %{
             "name" => "Luxembourg",
             "parent_key" => "continent_europe",
             "card" => %{
               "description" => "Spend time in Luxembourg.",
               "child_zoom" => 9.5
             }
           } = by_key["country_lu"]

    assert %{"continent" => "Antarctica", "parent_key" => nil} = by_key["country_aq"]

    File.write!(
      Path.join(root, "config/achievements.yml"),
      @hand <> "  continent: World\n  card: {rarity: Epic, place: Earth}\n"
    )

    [hand | _] =
      root
      |> Achievements.export(@translations)
      |> IO.iodata_to_binary()
      |> Jason.decode!()
      |> Map.fetch!("definitions")

    assert hand["continent"] == "World"
    assert hand["card"] == %{"rarity" => "Epic", "place" => "Earth"}
  end

  test "exports ordered default and locale transliteration rules with English fallback", %{
    tmp_dir: root
  } do
    File.write!(Path.join(root, "config/locales/rules.yml"), """
    en:
      i18n:
        transliterate:
          rule: {ø: oe, æ: ae}
    de:
      i18n:
        transliterate:
          rule: {ü: ue, ß: ss}
    """)

    data =
      root
      |> Achievements.export(@translations)
      |> IO.iodata_to_binary()
      |> Jason.decode!(objects: :ordered_objects)

    assert Enum.map(data.values, &elem(&1, 0)) == ~w(definitions transliteration)
    table = data["transliteration"]
    assert Enum.map(table.values, &elem(&1, 0)) == ~w(default rules)
    assert length(table["default"].values) == 195
    assert table["default"]["Æ"] == "AE"
    assert table["default"]["Ł"] == "L"
    assert table["default"]["ß"] == "ss"
    assert Enum.map(table["rules"].values, &elem(&1, 0)) == ~w(en de es fr pl ca zh)
    assert table["rules"]["de"].values == [{"ü", "ue"}, {"ß", "ss"}]
    assert table["rules"]["fr"].values == [{"ø", "oe"}, {"æ", "ae"}]
  end

  test "rejects non-hash transliteration rules", %{tmp_dir: root} do
    File.write!(
      Path.join(root, "config/locales/rules.yml"),
      "en: {i18n: {transliterate: {rule: invalid}}}"
    )

    assert_raise ArgumentError, "en: only hash transliteration rules can be exported", fn ->
      Achievements.export(root, @translations)
    end
  end
end

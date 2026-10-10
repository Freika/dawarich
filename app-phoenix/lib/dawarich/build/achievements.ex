defmodule Dawarich.Build.Achievements do
  @moduledoc false

  alias Dawarich.Build.Yaml
  alias Jason.OrderedObject

  @no_meta_continent "Antarctica"

  def export(root, translations) do
    planet =
      root
      |> Path.join("config/achievements/planet.yml")
      |> Yaml.load!()
      |> fetch!("continents")

    hand = root |> Path.join("config/achievements.yml") |> Yaml.load!()

    sets =
      hand_sets(hand, universe(planet)) ++ continent_sets(planet, hand) ++ country_sets(planet)

    Jason.encode_to_iodata!(
      object([
        {"definitions", Enum.map(sets, &json(&1, translations))},
        {"transliteration", Dawarich.Build.Transliteration.export(root)}
      ])
    )
  end

  defp universe(planet) do
    for {_continent, data} <- pairs(planet),
        {code, country} <- pairs(fetch(data, "countries")),
        reduce: [] do
      acc -> List.keystore(acc, code, 0, {code, fetch!(country, "name")})
    end
  end

  defp hand_sets(hand, universe) do
    for {key, attrs} <- pairs(hand), not String.starts_with?(key, "_") do
      regions = fetch(attrs, "regions")

      %{
        key: key,
        kind: fetch(attrs, "kind"),
        name: fetch(attrs, "name"),
        country: nil,
        continent: fetch(attrs, "continent"),
        parent_key: nil,
        card: fetch(attrs, "card") || object([]),
        level: "country",
        threshold: fetch(attrs, "threshold"),
        regions: if(regions, do: pairs(regions), else: universe),
        place: fetch(fetch(attrs, "card"), "place")
      }
    end
  end

  defp continent_sets(planet, hand) do
    for {continent, data} <- pairs(planet), continent != @no_meta_continent do
      %{
        key: continent_key(continent),
        kind: "continent",
        name: continent <> " Explorer",
        country: nil,
        continent: continent,
        parent_key: nil,
        card: continent_card(continent, data, hand),
        level: "country",
        threshold: nil,
        regions:
          for(
            {code, country} <- pairs(fetch(data, "countries")),
            do: {code, fetch!(country, "name")}
          ),
        place: continent
      }
    end
  end

  defp country_sets(planet) do
    for {continent, data} <- pairs(planet),
        {code, country} <- pairs(fetch!(data, "countries")) do
      name = fetch!(country, "name")
      subdivisions = pairs(fetch!(country, "subdivisions"))
      gridded = subdivisions != []

      %{
        key: "country_" <> String.downcase(code),
        kind: "country",
        name: if(gridded, do: name <> " Explorer", else: name),
        country: code,
        continent: continent,
        parent_key: if(continent == @no_meta_continent, do: nil, else: continent_key(continent)),
        card: country_card(country, gridded),
        level: if(gridded, do: "subdivision", else: "country"),
        threshold: nil,
        regions: if(gridded, do: subdivisions, else: [{code, name}]),
        place: name
      }
    end
  end

  defp continent_key(continent),
    do: "continent_" <> (continent |> String.downcase() |> String.replace(" ", "_"))

  defp continent_card(continent, data, hand) do
    meta = hand |> fetch!("_continents") |> fetch!(continent)
    count = data |> fetch!("countries") |> pairs() |> length()

    object([
      {"rarity", "Legendary"},
      {"description", "Spend time in all #{count} countries and territories of #{continent}."},
      {"flavor", fetch(meta, "flavor")},
      {"place", continent},
      {"child_zoom", fetch(meta, "child_zoom")},
      {"art", fetch(meta, "art")}
    ])
  end

  defp country_card(country, gridded) do
    name = fetch!(country, "name")
    count = country |> fetch!("subdivisions") |> pairs() |> length()
    art = fetch!(country, "art")

    description =
      if gridded,
        do: "Spend time in all #{count} regions of #{name}.",
        else: "Spend time in #{name}."

    object([
      {"rarity", "Rare"},
      {"description", description},
      {"place", name},
      {"child_zoom", Float.round(fetch!(art, "zoom") + 1.5, 1)},
      {"art", art}
    ])
  end

  defp json(set, translations) do
    flat = set.kind == "country" and set.level == "country"
    total = length(set.regions)

    names =
      for locale <- Dawarich.Build.I18n.locales(),
          do: {locale, name(set, flat, locale, translations)}

    object([
      {"key", set.key},
      {"kind", set.kind},
      {"level", set.level},
      {"flat", flat},
      {"threshold", set.threshold},
      {"total", total},
      {"target", set.threshold || total},
      {"regions", object(set.regions)},
      {"region_codes", Enum.map(set.regions, &elem(&1, 0))},
      {"names", object(names)},
      {"name", set.name},
      {"country", set.country},
      {"continent", set.continent},
      {"parent_key", set.parent_key},
      {"card", set.card}
    ])
  end

  defp name(%{kind: "region_set", name: name}, _flat, _locale, _translations), do: name
  defp name(%{place: place}, true, _locale, _translations), do: place

  defp name(%{place: place}, false, locale, translations) when is_binary(place) do
    {:ok, text} =
      Dawarich.I18n.lookup(translations, locale, "achievements.cards.explorer_name", %{
        "place" => place
      })

    text
  end

  defp object(pairs), do: %OrderedObject{values: pairs}

  defp pairs(%OrderedObject{values: values}), do: values
  defp pairs(nil), do: []

  defp fetch(%OrderedObject{} = object, key), do: object[key]
  defp fetch(nil, _key), do: nil

  defp fetch!(object, key),
    do: fetch(object, key) || raise(ArgumentError, "achievements: #{key} is missing")
end

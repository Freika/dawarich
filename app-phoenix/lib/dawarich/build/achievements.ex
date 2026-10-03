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
    sets = hand_sets(hand, universe(planet)) ++ continent_sets(planet) ++ country_sets(planet)

    Jason.encode_to_iodata!(object([{"definitions", Enum.map(sets, &json(&1, translations))}]))
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
        level: "country",
        threshold: fetch(attrs, "threshold"),
        regions: if(regions, do: pairs(regions), else: universe),
        place: fetch(fetch(attrs, "card"), "place")
      }
    end
  end

  defp continent_sets(planet) do
    for {continent, data} <- pairs(planet), continent != @no_meta_continent do
      %{
        key: "continent_" <> (continent |> String.downcase() |> String.replace(" ", "_")),
        kind: "continent",
        name: continent <> " Explorer",
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
    for {_continent, data} <- pairs(planet),
        {code, country} <- pairs(fetch!(data, "countries")) do
      name = fetch!(country, "name")
      subdivisions = pairs(fetch!(country, "subdivisions"))
      gridded = subdivisions != []

      %{
        key: "country_" <> String.downcase(code),
        kind: "country",
        name: name,
        level: if(gridded, do: "subdivision", else: "country"),
        threshold: nil,
        regions: if(gridded, do: subdivisions, else: [{code, name}]),
        place: name
      }
    end
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
      {"names", object(names)}
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

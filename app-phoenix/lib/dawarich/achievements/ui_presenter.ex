defmodule Dawarich.Achievements.UiPresenter do
  @moduledoc false
  alias Dawarich.Achievements.{Registry, UiText}

  def set(definition, state, sharing, locale, dates) do
    earned = Map.take(Map.get(state, "earned", %{}), definition.region_codes)
    count = map_size(earned)
    target = definition.target
    completed = count >= target
    card = definition.card

    %{
      "key" => definition.key,
      "name" => name(definition, locale),
      "place" => card["place"],
      "total" => definition.total,
      "target" => target,
      "count" => count,
      "percent" => if(target == 0, do: 0, else: min(round(count * 100 / target), 100)),
      "locked" => count == 0,
      "completed" => completed,
      "celebrate" => completed and blank?(get_in(state, ["celebrated", definition.key])),
      "parent_key" => definition.parent_key,
      "sharing_enabled" => sharing["sharing_enabled"] || false,
      "sharing_uuid" => sharing["sharing_uuid"],
      "completed_on" =>
        if(completed,
          do:
            earned
            |> Map.values()
            |> Enum.map(&dates[&1])
            |> Enum.sort(Date)
            |> Enum.at(target - 1),
          else: nil
        )
    }
  end

  def metadata(presenter), do: Map.delete(presenter, "completed_on")

  def card(definition, presenter, locale) do
    card = definition.card
    art = card["art"]
    marker = card["marker"] || art

    %{
      "name" => presenter["name"],
      "description" => description(definition, locale),
      "flavor" => card["flavor"],
      "rarity" => card["rarity"],
      "place" => card["place"],
      "map_lat" => art["lat"],
      "map_lon" => art["lon"],
      "map_zoom" => art["zoom"],
      "marker_lat" => marker["lat"],
      "marker_lon" => marker["lon"],
      "percent" => presenter["percent"],
      "completed" => presenter["completed"],
      "locked" => presenter["locked"],
      "earned_label" => label(definition, presenter, locale),
      "geography_key" => definition.key,
      "silhouette" => nil,
      "metric_label" => metric(definition, presenter, locale)
    }
  end

  def children(definition, state, locale, dates) do
    earned = Map.get(state, "earned", %{})

    definition.region_codes
    |> Enum.flat_map(fn code ->
      if definition.level == "subdivision" do
        art = definition.card["art"]
        date = earned[code]

        [
          %{
            "name" => definition.regions[code],
            "code" => code,
            "key" => nil,
            "rarity" => get_in(definition.card, ["rarities", code]) || "Common",
            "map_lat" => art["lat"],
            "map_lon" => art["lon"],
            "map_zoom" => definition.card["child_zoom"] || 6,
            "marker_lat" => art["lat"],
            "marker_lon" => art["lon"],
            "percent" => if(date, do: 100, else: 0),
            "completed" => not blank?(date),
            "locked" => blank?(date),
            "earned_label" => if(date, do: unlocked(locale, dates[date]), else: nil)
          }
        ]
      else
        case Registry.find("country_" <> String.downcase(code)) do
          nil -> []
          child -> [country(child, state, locale, dates, earned[code])]
        end
      end
    end)
    |> Enum.sort_by(&{if(&1["locked"], do: 1, else: 0), &1["name"]})
  end

  defp country(child, state, locale, dates, visited) do
    progress = set(child, state, %{}, locale, dates)
    art = child.card["art"]
    link = if(child.level == "subdivision", do: child.key, else: nil)

    label =
      cond do
        progress["completed"] or progress["percent"] > 0 -> label(child, progress, locale)
        not blank?(visited) -> UiText.t(locale, "cards.status.visited")
        true -> UiText.t(locale, "cards.status.locked")
      end

    %{
      "name" => child.card["place"],
      "code" => child.country,
      "key" => link,
      "share_key" => if(link, do: nil, else: child.key),
      "rarity" => child.card["rarity"],
      "map_lat" => art["lat"],
      "map_lon" => art["lon"],
      "map_zoom" => art["zoom"],
      "marker_lat" => art["lat"],
      "marker_lon" => art["lon"],
      "percent" => progress["percent"],
      "completed" => progress["completed"],
      "locked" => blank?(visited) and progress["locked"],
      "earned_label" => label
    }
  end

  defp name(d, locale) do
    cond do
      d.kind == "region_set" -> d.name
      d.flat -> d.card["place"]
      true -> UiText.t(locale, "cards.explorer_name", %{"place" => d.card["place"]})
    end
  end

  defp description(d, locale) do
    key =
      cond do
        d.kind == "continent" -> "continent"
        d.kind == "country" and d.level == "subdivision" -> "regions"
        d.kind == "country" -> "country"
        true -> nil
      end

    if key,
      do:
        UiText.t(locale, "cards.description." <> key, %{
          "count" => d.total,
          "place" => d.card["place"]
        }),
      else: d.card["description"]
  end

  defp label(d, p, locale) do
    cond do
      p["locked"] -> UiText.t(locale, "cards.status.locked")
      p["completed"] -> unlocked(locale, p["completed_on"])
      true -> metric(d, p, locale)
    end
  end

  defp metric(d, p, locale),
    do:
      UiText.t(
        locale,
        "cards.metric." <> if(d.level == "country", do: "countries", else: "regions"),
        %{"count" => min(p["count"], p["target"]), "total" => p["target"]}
      )

  defp unlocked(locale, date),
    do: UiText.t(locale, "cards.status.unlocked_on", %{"date" => UiText.date(locale, date)})

  defp blank?(v), do: v in [nil, false, "", [], %{}] or (is_binary(v) and String.trim(v) == "")
end

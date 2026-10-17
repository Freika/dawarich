defmodule Dawarich.Achievements.UnlockCard do
  @moduledoc false
  alias Dawarich.Achievements.{Registry, UiPresenter, UiSilhouettes, UiText}

  def call(repo, %{kind: "set", key: key}, state, context) do
    case Registry.find(key) do
      nil -> nil
      %{kind: "region_set"} -> nil
      definition -> set(repo, definition, state, context)
    end
  end

  def call(repo, event, state, context) do
    if event.key =~ ~r/\A[A-Z]{2}\z/ do
      case Registry.find("country_" <> String.downcase(event.key)) do
        nil -> nil
        definition -> country(repo, definition, state, context)
      end
    else
      subdivision(repo, event, context)
    end
  end

  defp set(repo, definition, state, context) do
    dates = UiText.local_dates(Map.values(Map.get(state, "earned", %{})), context.settings)
    progress = UiPresenter.set(definition, state, %{}, context.locale, dates)

    shape =
      if definition.kind == "country",
        do: UiSilhouettes.cards(repo, "country", [definition.country])[definition.country],
        else: UiSilhouettes.collection(repo, definition.region_codes, definition.key)

    attributes =
      UiPresenter.card(definition, progress, context.locale) |> Map.put("silhouette", shape)

    %{"attributes" => attributes, "path" => path(definition.key), "name" => attributes["name"]}
  end

  defp country(repo, definition, state, context) do
    card = set(repo, definition, state, context)
    attributes = card["attributes"]

    attributes =
      if not definition.flat and not attributes["completed"] do
        Map.merge(attributes, %{
          "name" => definition.card["place"],
          "description" => nil,
          "locked" => false,
          "earned_label" => UiText.t(context.locale, "cards.status.visited")
        })
      else
        attributes
      end

    destination = if definition.flat, do: definition.parent_key, else: definition.key

    destination =
      cond do
        is_nil(destination) -> "/achievements"
        definition.flat -> path(destination, definition.card["place"])
        true -> path(destination)
      end

    %{"attributes" => attributes, "path" => destination, "name" => attributes["name"]}
  end

  defp subdivision(repo, event, context) do
    case Registry.subdivision_parent(event.key) do
      nil ->
        nil

      definition ->
        name = Map.fetch!(definition.regions, event.key)
        art = definition.card["art"]
        instant = instant(event.created_at)
        date = UiText.local_dates([instant], context.settings)[instant]

        attributes = %{
          "name" => name,
          "rarity" => get_in(definition.card, ["rarities", event.key]) || "Common",
          "map_lat" => art["lat"],
          "map_lon" => art["lon"],
          "map_zoom" => art["zoom"],
          "percent" => 100,
          "completed" => true,
          "locked" => false,
          "earned_label" =>
            UiText.t(context.locale, "cards.status.unlocked_on", %{
              "date" => UiText.date(context.locale, date)
            }),
          "geography_key" => event.key,
          "silhouette" => UiSilhouettes.cards(repo, "subdivision", [event.key])[event.key]
        }

        %{"attributes" => attributes, "path" => path(definition.key, name), "name" => name}
    end
  end

  defp instant(%NaiveDateTime{} = at),
    do: at |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_iso8601()

  defp instant(%DateTime{} = at), do: DateTime.to_iso8601(at)
  defp path(key), do: "/achievements/" <> key
  defp path(key, name), do: path(key) <> "?" <> URI.encode_query(%{"q" => name}) <> "#collection"
end

defmodule Dawarich.Achievements.Collection do
  @moduledoc false
  alias Dawarich.Achievements.{Celebrations, Registry, UiPresenter, UiSilhouettes, UiText}

  def load(repo, user_id, params, context) do
    case route(params["key"]) do
      {:ok, definition} -> build(repo, user_id, definition, params, context)
      error -> error
    end
  end

  def route(nil), do: {:ok, nil}

  def route(key) do
    case Registry.find(key) do
      nil -> {:error, :not_found}
      %{kind: "region_set"} -> {:redirect, "/achievements"}
      %{flat: true, parent_key: nil} -> {:error, :not_found}
      %{flat: true, parent_key: parent} -> {:redirect, "/achievements/" <> parent}
      definition -> {:ok, definition}
    end
  end

  defp build(repo, user_id, definition, params, c) do
    state =
      case query(
             repo,
             "SELECT state FROM achievement_progresses WHERE user_id=$1 AND achievement_key='exploration'",
             [user_id]
           ) do
        [[state]] -> state
        [] -> %{}
      end

    c =
      Map.put(
        c,
        :dates,
        UiText.local_dates(Map.values(Map.get(state, "earned", %{})), c.settings)
      )

    definitions = Registry.all()
    continents = Enum.filter(definitions, &(&1.kind == "continent"))
    orphans = Enum.filter(definitions, &(&1.kind == "country" and is_nil(&1.parent_key)))

    carriers =
      carriers(
        repo,
        user_id,
        Enum.map(continents ++ orphans ++ if(definition, do: [definition], else: []), & &1.key)
      )

    present = fn d ->
      UiPresenter.set(d, state, Map.get(carriers, d.key, %{}), c.locale, c.dates)
    end

    view = %{
      continents: Enum.map(continents, &(present.(&1) |> UiPresenter.metadata())),
      orphans: Enum.map(orphans, &(present.(&1) |> UiPresenter.metadata())),
      summary: summary(definitions, state)
    }

    {view, celebrate} =
      if definition do
        p = present.(definition)

        {detail(repo, user_id, view, definition, p, state, params, c),
         if(p["celebrate"], do: [p["key"]], else: [])}
      else
        rendered = Enum.map(continents, &hydrate(repo, &1, present.(&1), c.locale))
        orphan_cards = Enum.map(orphans, &hydrate(repo, &1, present.(&1), c.locale))

        {view |> Map.put(:sets, rendered) |> Map.put(:orphans, orphan_cards),
         Enum.filter(rendered ++ orphan_cards, & &1["celebrate"]) |> Enum.map(& &1["key"])}
      end

    clock = Map.get(c, :clock, fn -> c.now end)

    :ok =
      Celebrations.record_seen!(repo, user_id, celebrate, fn ->
        UiText.timestamp(c.settings, clock.())
      end)

    {:ok, view}
  end

  defp detail(repo, user_id, view, d, p, state, params, c) do
    q = UiText.query(params["q"] || "")

    status =
      if(params["status"] in ~w(all unlocked in_progress locked),
        do: params["status"],
        else: "all"
      )

    all =
      UiPresenter.children(d, state, c.locale, c.dates)
      |> Enum.filter(
        &(matches?(&1, status) and
            String.contains?(UiText.search(&1["name"], c.locale), UiText.search(q, c.locale)))
      )

    page = max(page(params["page"]), 1)
    children = all |> Enum.slice((page - 1) * 12, 12)
    codes = Enum.map(children, & &1["code"])
    shapes = UiSilhouettes.cards(repo, d.level, codes)

    centroids =
      if d.level == "subdivision" and codes != [],
        do:
          query(
            repo,
            "SELECT code,ST_Y(ST_PointOnSurface(geom::geometry)),ST_X(ST_PointOnSurface(geom::geometry)) FROM regions WHERE code=ANY($1)",
            [codes]
          )
          |> Map.new(fn [code, lat, lon] -> {code, {lat, lon}} end),
        else: %{}

    shares =
      carriers(
        repo,
        user_id,
        Enum.flat_map(children, fn card ->
          if card["share_key"], do: [card["share_key"]], else: []
        end)
      )

    children =
      Enum.map(children, fn card ->
        code = card["code"]

        geography =
          if(d.level == "country", do: "country_" <> String.downcase(code), else: code)

        card = Map.put(card, "geography_key", geography)
        card = Map.put(card, "silhouette", shapes[code])

        card =
          case centroids[code] do
            {lat, lon} when not is_nil(lat) and not is_nil(lon) ->
              Map.merge(card, %{
                "map_lat" => lat,
                "map_lon" => lon,
                "marker_lat" => lat,
                "marker_lon" => lon
              })

            _ ->
              card
          end

        if card["share_key"] do
          carrier = Map.get(shares, card["share_key"], %{})

          Map.put(card, "share", %{
            "key" => card["share_key"],
            "shared" => carrier["sharing_enabled"] || false,
            "uuid" => carrier["sharing_uuid"]
          })
        else
          card
        end
      end)

    Map.merge(view, %{
      set: hydrate(repo, d, p, c.locale),
      children: children,
      query: q,
      status: status,
      sidebar_key: d.parent_key || d.key,
      page: page,
      pages: ceil(length(all) / 12),
      total: length(all),
      level: d.level,
      continent: d.continent,
      completed_on: p["completed_on"]
    })
  end

  defp hydrate(repo, d, p, locale) do
    shape =
      if(d.kind == "country",
        do: UiSilhouettes.cards(repo, "country", [d.country])[d.country],
        else: UiSilhouettes.collection(repo, d.region_codes, d.key)
      )

    card = UiPresenter.card(d, p, locale) |> Map.put("silhouette", shape)
    p |> UiPresenter.metadata() |> Map.put("card", card)
  end

  defp summary(definitions, state) do
    countries =
      definitions |> Enum.filter(&(&1.kind == "country")) |> MapSet.new(& &1.country)

    subdivisions =
      definitions
      |> Enum.filter(&(&1.level == "subdivision"))
      |> Enum.flat_map(& &1.region_codes)
      |> MapSet.new()

    earned = Map.get(state, "earned", %{}) |> Map.keys() |> MapSet.new()
    count = MapSet.intersection(earned, countries) |> MapSet.size()

    %{
      earned_countries: count,
      total_countries: MapSet.size(countries),
      earned_subdivisions: MapSet.intersection(earned, subdivisions) |> MapSet.size(),
      total_subdivisions: MapSet.size(subdivisions),
      percent:
        if(MapSet.size(countries) == 0, do: 0, else: round(count * 100 / MapSet.size(countries)))
    }
  end

  defp carriers(repo, user_id, keys),
    do:
      query(
        repo,
        "SELECT achievement_key,sharing_enabled,sharing_uuid FROM achievement_progresses WHERE user_id=$1 AND achievement_key=ANY($2)",
        [user_id, keys]
      )
      |> Map.new(fn [key, enabled, uuid] ->
        {key, %{"sharing_enabled" => enabled, "sharing_uuid" => uuid}}
      end)

  defp matches?(_card, "all"), do: true
  defp matches?(card, "unlocked"), do: card["completed"]
  defp matches?(card, "in_progress"), do: not card["locked"] and not card["completed"]
  defp matches?(card, "locked"), do: card["locked"]

  defp page(value), do: DawarichWeb.Params.ruby_to_i(value || "1")

  defp query(repo, sql, args), do: repo.query!(sql, args, log: false).rows
end

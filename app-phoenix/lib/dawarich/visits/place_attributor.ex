defmodule Dawarich.Visits.PlaceAttributor do
  @moduledoc false

  require Logger

  alias Dawarich.{Geo, RubyInteger}
  alias Dawarich.Geocoding.{Normalizer, Search}
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias Dawarich.Visits.{NamesSuggester, PlaceFinder}

  @streetish_osm_keys ~w(highway place boundary landuse natural waterway railway)

  @known_sql """
  SELECT p.id, p.name, p.source = 0, COALESCE(ST_Y(p.lonlat::geometry), p.latitude::float8),
         COALESCE(ST_X(p.lonlat::geometry), p.longitude::float8),
         (SELECT count(*) FROM visits v WHERE v.user_id = $1 AND v.place_id = p.id
            AND v.deleted_at IS NULL AND v.status != 2 AND v.status = 1)
  FROM places p
  WHERE p.user_id = $1
    AND ST_DWithin(p.lonlat::geography, ST_SetSRID(ST_MakePoint($3, $2), 4326)::geography, $4)
  ORDER BY p.id
  """

  def areas(repo, user_id) do
    for [id, name, lat, lon, radius] <-
          repo.query!(
            "SELECT id, name, latitude::float8, longitude::float8, radius FROM areas WHERE user_id = $1 ORDER BY id",
            [user_id],
            log: false
          ).rows,
        do: %{id: id, name: name, lat: lat, lon: lon, radius: radius}
  end

  def attribute(ctx, stay) do
    center = {stay.center_lat, stay.center_lon}

    with nil <- Enum.find(ctx.areas, &(Geo.distance_m(center, {&1.lat, &1.lon}) <= &1.radius)),
         nil <- known_place(ctx, stay, center) do
      unlabeled(ctx, stay)
    else
      %{radius: _} = area -> %{area: area.id, place: nil, name: area.name, evidence: :area}
      place -> %{area: nil, place: place.id, name: place.name, evidence: :place}
    end
  end

  defp known_place(ctx, stay, center) do
    candidates =
      for [id, name, manual, lat, lon, history] <-
            ctx.repo.query!(
              @known_sql,
              [ctx.user_id, stay.center_lat, stay.center_lon, ctx.policy.attribution_radius_m],
              log: false
            ).rows,
          do: %{
            id: id,
            name: name,
            rank: {if(manual, do: 0, else: 1), -history, Geo.distance_m(center, {lat, lon})}
          }

    if candidates == [], do: nil, else: Enum.min_by(candidates, & &1.rank)
  end

  defp unlabeled(ctx, stay) do
    poi_name = poi_vote(ctx, stay)
    lookup = if poi_name, do: nil, else: reverse_lookup(ctx, stay)
    poi_name = poi_name || venue_name(ctx, stay, lookup)

    if poi_name do
      place =
        PlaceFinder.mint(
          ctx.repo,
          ctx.user_id,
          stay.center_lat,
          stay.center_lon,
          poi_name,
          ctx.config.enabled
        )

      %{area: nil, place: place, name: poi_name, evidence: :poi}
    else
      case address_name(lookup) do
        address when address not in [nil, false] ->
          %{area: nil, place: nil, name: address, evidence: :address}

        _ ->
          %{area: nil, place: nil, name: nil, evidence: :none}
      end
    end
  end

  defp poi_vote(_ctx, %{point_ids: []}), do: nil

  defp poi_vote(ctx, stay) do
    geodata =
      for [g] <-
            ctx.repo.query!(
              "SELECT geodata FROM points WHERE user_id = $1 AND id = ANY($2) AND geodata != '{}' ORDER BY id",
              [ctx.user_id, stay.point_ids],
              log: false
            ).rows,
          do: g

    if geodata == [], do: nil, else: NamesSuggester.call(geodata)
  end

  defp reverse_lookup(%{config: %{enabled: false}}, _stay), do: nil

  defp reverse_lookup(ctx, stay) do
    case Search.reverse(ctx.config, {stay.center_lat, stay.center_lon},
           limit: 1,
           distance_sort: true
         ) do
      {:ok, [first | _]} ->
        Normalizer.from_data(first)

      {:ok, []} ->
        nil

      {:error, reason} ->
        Logger.warning(
          "[Visits::Detection::PlaceAttributor] reverse lookup failed: #{inspect(reason)}"
        )

        nil
    end
  rescue
    e ->
      Logger.warning(
        "[Visits::Detection::PlaceAttributor] reverse lookup failed: #{inspect(e.__struct__)}"
      )

      nil
  end

  defp venue_name(ctx, stay, %{properties: props, coords: coords}) do
    if Ruby.present?(props) and Ruby.present?(props["name"]) and
         props["osm_key"] not in @streetish_osm_keys and
         inside?(ctx, stay, coords),
       do: props["name"]
  end

  defp venue_name(_ctx, _stay, _lookup), do: nil

  defp inside?(ctx, stay, [lon, lat | _]) do
    case {to_f(lat), to_f(lon)} do
      {lat, lon} when is_float(lat) and is_float(lon) ->
        Geo.distance_m({stay.center_lat, stay.center_lon}, {lat, lon}) <=
          max(RubyInteger.to_i(stay.radius), ctx.policy.attribution_radius_m)

      _ ->
        false
    end
  end

  defp inside?(_ctx, _stay, _coords), do: false

  defp address_name(%{properties: props}) do
    street_line =
      [props["street"], props["housenumber"]]
      |> Enum.filter(&Ruby.present?/1)
      |> Enum.map_join(" ", &Ruby.to_s/1)

    cond do
      Ruby.blank?(props) -> nil
      Ruby.present?(street_line) -> street_line
      props["osm_key"] in @streetish_osm_keys -> props["name"]
      true -> nil
    end
  end

  defp address_name(_lookup), do: nil

  defp to_f(value) when is_float(value), do: value
  defp to_f(value) when is_integer(value), do: value * 1.0
  defp to_f(value) when is_binary(value), do: Ruby.to_f(value)
  defp to_f(_value), do: nil
end

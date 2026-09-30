defmodule Dawarich.Geocoding.PlaceFetch do
  @moduledoc false

  require Logger

  alias Dawarich.Geocoding.{Normalizer, PlaceAttributes, Search}
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  @load "SELECT id, user_id, name, latitude::text, longitude::text, ST_X(lonlat::geometry), " <>
          "ST_Y(lonlat::geometry), geodata, name_locked_at IS NOT NULL, source FROM places WHERE id = $1"
  @update "UPDATE places SET lonlat = ST_SetSRID(ST_MakePoint(longitude::float8, latitude::float8), 4326)::geography, " <>
            "city = $2, country = $3, geodata = $4, reverse_geocoded_at = $5, updated_at = $5, name = $6, " <>
            "source = $7 WHERE id = $1"
  @existing "SELECT id, user_id, name, latitude::text, longitude::text, ST_X(lonlat::geometry), " <>
              "ST_Y(lonlat::geometry), geodata, name_locked_at IS NOT NULL, source, " <>
              "geodata->'properties'->>'osm_id' FROM places " <>
              "WHERE geodata->'properties'->>'osm_id' = ANY($1) AND user_id = $2 ORDER BY id"
  @insert "INSERT INTO places (user_id, name, latitude, longitude, lonlat, city, country, geodata, source, " <>
            "created_at, updated_at) VALUES ($1, $2, $3::text::numeric, $4::text::numeric, " <>
            "ST_SetSRID(ST_MakePoint($5, $6), 4326)::geography, $7, $8, $9, $10, $11, $11) ON CONFLICT DO NOTHING"
  @upsert "INSERT INTO places (id, user_id, name, latitude, longitude, lonlat, city, country, geodata, source, " <>
            "created_at, updated_at) VALUES ($1, $2, $3, $4::text::numeric, $5::text::numeric, " <>
            "ST_SetSRID(ST_MakePoint($6, $7), 4326)::geography, $8, $9, $10, $11, $12, $12) " <>
            "ON CONFLICT (id) DO UPDATE SET user_id = EXCLUDED.user_id, name = EXCLUDED.name, " <>
            "latitude = EXCLUDED.latitude, longitude = EXCLUDED.longitude, lonlat = EXCLUDED.lonlat, " <>
            "city = EXCLUDED.city, country = EXCLUDED.country, geodata = EXCLUDED.geodata, " <>
            "source = EXCLUDED.source, updated_at = EXCLUDED.updated_at"
  @retries 3

  def run(repo, place_id, config) do
    case load(repo, @load, [place_id]) do
      [] ->
        Logger.warning("event=geocoding.place_missing place_id=#{place_id}")
        :missing

      [_place] when not config.enabled ->
        Logger.warning("event=geocoding.place_disabled place_id=#{place_id}")
        :ok

      [place] ->
        case lookup(place, config) do
          [] ->
            :ok

          [first | rest] ->
            update_queried!(repo, place, Normalizer.place(first), config.store_geodata)
            save_siblings!(repo, place.user_id, rest, config.store_geodata)
        end
    end
  end

  defp lookup(place, config) do
    lat = place.y || Ruby.to_f(place.latitude)
    lon = place.x || Ruby.to_f(place.longitude)

    case Search.reverse(config, {lat, lon}, limit: 10, distance_sort: true, radius: 1) do
      {:ok, results} ->
        results

      {:error, class} ->
        Logger.error("event=geocoding.place_lookup_failed place_id=#{place.id} class=#{class}")
        []
    end
  rescue
    exception ->
      Logger.error(
        "event=geocoding.place_lookup_failed place_id=#{place.id} class=#{inspect(exception.__struct__)}"
      )

      []
  end

  defp update_queried!(repo, place, data, store_geodata) do
    PlaceAttributes.queried_coordinates!(data)
    updated = PlaceAttributes.populate(place, data, store_geodata)
    PlaceAttributes.validate_name!(updated.name)
    now = NaiveDateTime.utc_now()

    repo.query!(
      @update,
      [
        place.id,
        updated.city,
        updated.country,
        updated.geodata,
        now,
        updated.name,
        updated.source
      ],
      log: false
    )
  end

  defp save_siblings!(_repo, _user_id, [], _store_geodata), do: :ok

  defp save_siblings!(repo, user_id, rest, store_geodata) do
    results = Enum.map(rest, &Normalizer.place/1)
    osm_ids = Enum.map(results, &PlaceAttributes.osm_key/1)
    existing = Map.new(load(repo, @existing, [osm_ids, user_id]), &{&1.osm_key, &1})

    {_known, creates, updates} =
      Enum.reduce(results, {existing, [], %{}}, fn data, {known, creates, updates} ->
        osm = PlaceAttributes.osm_key(data)

        case known[osm] do
          nil ->
            created =
              user_id
              |> PlaceAttributes.new_place(data)
              |> PlaceAttributes.populate(data, store_geodata)

            {known, [created | creates], updates}

          place ->
            updated =
              place
              |> PlaceAttributes.populate(data, store_geodata)
              |> PlaceAttributes.fill_lonlat(data)

            {Map.put(known, osm, updated), creates, Map.put(updates, updated.id, updated)}
        end
      end)

    now = NaiveDateTime.utc_now()
    creates = creates |> Enum.reverse() |> Enum.uniq_by(&PlaceAttributes.osm_id/1)

    write!(repo, creates, fn p ->
      {@insert, [p.user_id, p.name, p.latitude, p.longitude, p.x, p.y] ++ tail(p, now)}
    end)

    updates = updates |> Map.values() |> Enum.sort_by(& &1.id)

    write!(repo, updates, fn p ->
      {@upsert, [p.id, p.user_id, p.name, p.latitude, p.longitude, p.x, p.y] ++ tail(p, now)}
    end)
  end

  defp tail(place, now), do: [place.city, place.country, place.geodata, place.source, now]

  defp write!(_repo, [], _statement), do: :ok

  defp write!(repo, places, statement) do
    with_deadlock_retry(
      fn ->
        repo.transaction(fn ->
          Enum.each(places, fn place ->
            {sql, params} = statement.(place)
            repo.query!(sql, params, log: false)
          end)
        end)
      end,
      1
    )

    :ok
  end

  defp with_deadlock_retry(fun, attempt) do
    fun.()
  rescue
    error in Postgrex.Error ->
      if (error.postgres || %{})[:code] == :deadlock_detected and attempt <= @retries do
        Process.sleep(100 * attempt)
        with_deadlock_retry(fun, attempt + 1)
      else
        reraise error, __STACKTRACE__
      end
  end

  defp load(repo, sql, params) do
    for [id, user_id, name, latitude, longitude, x, y, geodata, locked, source | osm] <-
          repo.query!(sql, params, log: false).rows do
      %{
        id: id,
        user_id: user_id,
        name: name,
        latitude: latitude,
        longitude: longitude,
        x: x,
        y: y,
        geodata: geodata,
        name_locked: locked,
        source: source,
        city: nil,
        country: nil,
        osm_key: List.first(osm)
      }
    end
  end
end

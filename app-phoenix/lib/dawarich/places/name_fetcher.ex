defmodule Dawarich.Places.NameFetcher do
  @moduledoc false
  require Logger
  alias Dawarich.Geocoding.{Normalizer, PlaceAttributes, Search}
  alias Dawarich.Places.NameBuilder
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  def run(repo, user, id, config) do
    case lookup(repo, user, id, config) do
      {:ok, data} -> apply(repo, user, id, data, config)
      outcome -> outcome
    end
  end

  def lookup(repo, user, id, config) do
    case repo.query!(
           "SELECT COALESCE(ST_Y(lonlat::geometry),latitude::float8), COALESCE(ST_X(lonlat::geometry),longitude::float8) FROM places WHERE id=$1 AND user_id=$2",
           [id, user],
           log: false
         ).rows do
      [] -> :missing
      [_] when not config.enabled -> :ok
      [[lat, lon]] -> fetch(id, config, {lat, lon})
    end
  end

  def apply(repo, user, id, data, config) do
    if repo.in_transaction?() do
      write(repo, user, id, data, config)
    else
      {:ok, result} = repo.transaction(fn -> write(repo, user, id, data, config) end)
      result
    end
  end

  defp write(repo, user, id, data, config) do
    repo.query!("SAVEPOINT place_name_write", [], log: false)

    try do
      case repo.query!(
             "SELECT name,name_locked_at,city,country,geodata FROM places WHERE id=$1 AND user_id=$2 FOR UPDATE",
             [id, user],
             log: false
           ).rows do
        [[previous, locked, city, country, geodata]] ->
          props = Normalizer.from_data(data).properties
          built = NameBuilder.build(props)
          name = if is_nil(locked) and Ruby.present?(built), do: built, else: previous
          PlaceAttributes.validate_name!(name)

          city =
            if Ruby.present?(props["city"]), do: PlaceAttributes.cast!(props["city"]), else: city

          country =
            if Ruby.present?(props["country"]),
              do: PlaceAttributes.cast!(props["country"]),
              else: country

          geodata = if config.store_geodata, do: data, else: geodata

          repo.query!(
            "UPDATE places SET name=$3,city=$4,country=$5,geodata=$6,lonlat=ST_SetSRID(ST_MakePoint(longitude::float8,latitude::float8),4326)::geography,updated_at=$7 WHERE id=$1 AND user_id=$2",
            [id, user, name, city, country, geodata, NaiveDateTime.utc_now()],
            log: false
          )

          if Ruby.present?(name) do
            stale = Enum.uniq(["Suggested place", previous]) -- [name]

            repo.query!(
              "UPDATE visits SET name=$3 WHERE place_id=$1 AND name=ANY($2)",
              [id, stale, name],
              log: false
            )
          end

        [] ->
          :ok
      end

      :ok
      repo.query!("RELEASE SAVEPOINT place_name_write", [], log: false)
      :ok
    rescue
      error ->
        repo.query!("ROLLBACK TO SAVEPOINT place_name_write", [], log: false)
        repo.query!("RELEASE SAVEPOINT place_name_write", [], log: false)

        Logger.error(
          "event=geocoding.name_write_failed place_id=#{id} class=#{inspect(error.__struct__)}"
        )

        :ok
    end
  end

  defp fetch(id, config, coords) do
    case Search.reverse(config, coords, limit: 1, distance_sort: true) do
      {:ok, [data | _]} ->
        props = Normalizer.from_data(data).properties
        if map_size(props) > 0, do: {:ok, data}, else: :ok

      {:ok, []} ->
        :ok

      {:error, class} ->
        Logger.warning("event=geocoding.name_lookup_failed place_id=#{id} class=#{class}")
        :ok
    end
  rescue
    error ->
      Logger.error(
        "event=geocoding.name_lookup_failed place_id=#{id} class=#{inspect(error.__struct__)}"
      )

      :ok
  end
end

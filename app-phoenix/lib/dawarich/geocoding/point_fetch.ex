defmodule Dawarich.Geocoding.PointFetch do
  @moduledoc false

  require Logger

  alias Dawarich.Geocoding.{Countries, Result, Search}
  alias Dawarich.RailsEffects
  alias Dawarich.ReleaseMigrations.Effects.Support.{Ruby, RubyFloat}
  alias Dawarich.Stats.GeocodedDays

  @load "SELECT id, user_id, timestamp, lock_version, reverse_geocoded_at IS NOT NULL, " <>
          "ST_Y(lonlat::geometry), ST_X(lonlat::geometry), city, country_name, country_id " <>
          "FROM points WHERE id = $1"
  @empty "UPDATE points SET reverse_geocoded_at = $2, updated_at = $2, lock_version = lock_version + 1 " <>
           "WHERE id = $1 AND lock_version = $3"
  @write "UPDATE points SET city = $2, country_name = $3, country_id = $4, geodata = $5, " <>
           "reverse_geocoded_at = $6, updated_at = $6, lock_version = lock_version + 1 " <>
           "WHERE id = $1 AND lock_version = $7"
  @transient [
    :timeout,
    :network,
    :econnrefused,
    :nxdomain,
    :service_unavailable,
    :response_parse_error
  ]
  @contention [:deadlock_detected, :lock_not_available, :query_canceled]
  @retries 3

  def run(repo, id, config, force), do: attempt(repo, id, config, force, 0)

  defp attempt(repo, id, config, force, stale) do
    case load(repo, id) do
      nil ->
        if stale == 0, do: Logger.warning("event=geocoding.point_missing point_id=#{id}")
        :missing

      point ->
        if eligible?(point, force),
          do: retry_stale(repo, point, config, force, stale),
          else: :skipped
    end
  end

  defp retry_stale(repo, point, config, force, stale) do
    case geocode(repo, point, config) do
      :stale when stale < @retries ->
        attempt(repo, point.id, config, force, stale + 1)

      :stale ->
        Logger.error("event=geocoding.point_stale point_id=#{point.id}")
        :stale

      outcome ->
        outcome
    end
  end

  defp eligible?(point, force),
    do:
      (force or not point.geocoded) and not is_nil(point.timestamp) and not is_nil(point.lat) and
        not is_nil(point.lon)

  defp geocode(repo, point, config) do
    case Search.reverse(config, {point.lat, point.lon}, []) do
      {:ok, []} ->
        with :ok <- commit(repo, @empty, [point.id, now(), point.lock_version], point), do: :empty

      {:ok, [data | _]} ->
        if Ruby.present?(Ruby.index(data, "error")),
          do: :skipped,
          else: write(repo, point, config, data)

      {:error, class} ->
        provider_error(point.id, class)
    end
  rescue
    exception ->
      Logger.error(
        "event=geocoding.point_error point_id=#{point.id} class=#{inspect(exception.__struct__)}"
      )

      :error
  end

  defp write(repo, point, config, data) do
    country = Result.country(config.provider, data)

    with {:ok, city} <- cast(Result.city(config.provider, data)),
         {:ok, country_name} <- cast(country) do
      country_id =
        if country not in [nil, false], do: country_id(repo, config, data, country_name)

      geodata = if config.store_geodata, do: data, else: %{}
      params = [point.id, city, country_name, country_id, geodata, now(), point.lock_version]

      with :ok <- commit(repo, @write, params, point) do
        if {city, country_name, country_id} != {point.city, point.country_name, point.country_id},
          do: mark(repo, point)

        :written
      end
    else
      {:error, :unsupported_value} ->
        Logger.error("event=geocoding.point_error point_id=#{point.id} class=unsupported_value")
        :error
    end
  end

  defp country_id(repo, config, data, name) do
    code =
      try do
        Result.country_code(config.provider, data)
      rescue
        _ -> nil
      end

    case Countries.find(repo, name, code) do
      %{id: id} -> id
      nil -> nil
    end
  end

  defp commit(repo, sql, params, point) do
    transaction = fn ->
      repo.transaction(fn ->
        case repo.query!(sql, params, log: false) do
          %{num_rows: 1} -> RailsEffects.tile_epoch(repo, point.user_id, [point.timestamp])
          %{num_rows: 0} -> repo.rollback(:stale)
        end
      end)
    end

    case with_write_retry(transaction, 1) do
      {:ok, :ok} -> :ok
      {:error, :stale} -> :stale
    end
  end

  defp with_write_retry(fun, attempt) do
    fun.()
  rescue
    error in Postgrex.Error ->
      if (error.postgres || %{})[:code] in @contention and attempt <= @retries do
        Process.sleep(100 * attempt + :rand.uniform(50))
        with_write_retry(fun, attempt + 1)
      else
        reraise error, __STACKTRACE__
      end
  end

  defp mark(repo, point) do
    GeocodedDays.mark(repo, point.user_id, point.timestamp)
  rescue
    error in [DBConnection.ConnectionError, Postgrex.Error] ->
      Logger.warning(
        "event=geocoding.geocoded_day_failed user_id=#{point.user_id} reason=#{inspect(error.__struct__)}"
      )
  end

  defp provider_error(id, class) do
    level = if class in @transient, do: :warning, else: :error
    Logger.log(level, "event=geocoding.point_provider_error point_id=#{id} class=#{class}")
    :error
  end

  defp cast(nil), do: {:ok, nil}
  defp cast(value) when is_binary(value), do: {:ok, value}
  defp cast(true), do: {:ok, "t"}
  defp cast(false), do: {:ok, "f"}
  defp cast(value) when is_integer(value), do: {:ok, Integer.to_string(value)}
  defp cast(value) when is_float(value), do: {:ok, RubyFloat.to_s(value)}
  defp cast(_value), do: {:error, :unsupported_value}

  defp now, do: NaiveDateTime.utc_now()

  defp load(repo, id) do
    case repo.query!(@load, [id], log: false).rows do
      [[id, user_id, timestamp, version, geocoded, lat, lon, city, country, country_id]] ->
        %{
          id: id,
          user_id: user_id,
          timestamp: timestamp,
          lock_version: version,
          geocoded: geocoded,
          lat: lat,
          lon: lon,
          city: city,
          country_name: country,
          country_id: country_id
        }

      [] ->
        nil
    end
  end
end

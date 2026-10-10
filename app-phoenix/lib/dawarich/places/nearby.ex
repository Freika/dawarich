defmodule Dawarich.Places.Nearby do
  @moduledoc false
  require Logger
  alias Dawarich.{Geocoding.Config, Geocoding.Search, PlacesApi, Repo, TtlCache}

  def fetch(user, lat, lon, radius, limit, opts \\ []) do
    config = opts[:config] || Config.resolve(opts[:repo] || Repo)

    cond do
      not config.enabled or (lat == 0 and lon == 0) ->
        []

      opts[:cache] ->
        TtlCache.fetch(
          {__MODULE__, cache_key(config, lat, lon, radius, limit)},
          3_600_000,
          fn -> lookup(user, config, lat, lon, radius, limit) end,
          cache_nil: false
        ) || []

      true ->
        lookup(user, config, lat, lon, radius, limit) || []
    end
  rescue
    error ->
      Logger.error("event=places.nearby_failed error=#{inspect(error.__struct__)}")
      Sentry.capture_exception(error, stacktrace: __STACKTRACE__, handled: true)
      []
  end

  def cache_key(config, lat, lon, radius, limit) do
    digest =
      [config.source, config.provider, config.host, config.use_https, config.api_key]
      |> Enum.map_join("|", &if(is_nil(&1), do: "", else: to_string(&1)))
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)

    "places_nearby:#{digest}:#{Float.round(lat * 1.0, 4)},#{Float.round(lon * 1.0, 4)},r=#{radius},l=#{limit}"
  end

  defp lookup(_user, config, lat, lon, radius, limit) do
    case Search.nearby(config, {lat, lon}, limit: limit, radius: radius, distance_sort: true) do
      {:ok, results} ->
        Enum.map(results, &PlacesApi.Nearby.format(&1, lat, lon))

      {:error, reason} ->
        message =
          "event=places.nearby_provider_error reason=#{reason} radius=#{radius} limit=#{limit}"

        if reason in [
             :timeout,
             :tls,
             :network,
             :nxdomain,
             :econnrefused,
             :service_unavailable,
             :response_parse_error,
             :invalid_request
           ] do
          Logger.warning(message)
        else
          Logger.error(message)

          Sentry.capture_exception(
            RuntimeError.exception("Places::NearbySearch failed: #{reason}"),
            handled: true
          )
        end

        nil

      nil ->
        nil
    end
  end
end

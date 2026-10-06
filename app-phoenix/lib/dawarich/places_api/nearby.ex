defmodule Dawarich.PlacesApi.Nearby do
  @moduledoc false
  alias Dawarich.{Geo, I18n, Repo}
  alias Dawarich.Ingest.Ruby
  alias Dawarich.Locations.Suggestions
  alias Dawarich.Photos.ProviderCache

  @fields ~w(id name latitude longitude osm_id osm_type osm_key osm_value city country street housenumber postcode source geodata)
  def term(%{"places" => list}), do: {:object, [{"places", Enum.map(list, &item_term/1)}]}
  def term(other), do: other

  def item_term(map),
    do:
      {:object,
       for(key <- @fields, Map.has_key?(map, key), do: {key, ProviderCache.wire(map[key])})}

  def run(user, params) do
    if Ruby.present?(params["latitude"]) and Ruby.present?(params["longitude"]) do
      places =
        fetch(
          user,
          Ruby.to_f(params["latitude"]),
          Ruby.to_f(params["longitude"]),
          number(params["radius"], 0.5),
          count(params["limit"], 10)
        )

      {:ok, 200, %{"places" => places}}
    else
      {:ok, 400,
       %{"error" => I18n.en!("controllers.api.v1.places.latitude_and_longitude_are_required")}}
    end
  rescue
    _ -> {:ok, 500, %{"error" => "Internal Server Error"}}
  end

  def fetch(user, lat, lon, radius, limit, opts \\ []) do
    config = Suggestions.configuration()

    cond do
      not config.enabled or (lat == 0 and lon == 0) ->
        []

      opts[:cache] ->
        key = cache_key(config, lat, lon, radius, limit)

        case ProviderCache.get(key) do
          {:ok, list} when is_list(list) ->
            list

          _ ->
            results = lookup(user, lat, lon, radius, limit)
            if results, do: ProviderCache.put(key, results, 3600)
            results || []
        end

      true ->
        lookup(user, lat, lon, radius, limit) || []
    end
  rescue
    _ -> []
  end

  defp lookup(user, lat, lon, radius, limit) do
    case Suggestions.lookup(user, {lat, lon}, limit: limit, radius: radius, distance_sort: true) do
      nil -> nil
      results -> Enum.map(results, &format(&1, lat, lon))
    end
  end

  def cache_key(config, lat, lon, radius, limit) do
    digest =
      [config.source, config.provider, config.host, config.use_https, config.api_key]
      |> Enum.map_join("|", &if(is_nil(&1), do: "", else: to_string(&1)))
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)

    "places_nearby:#{digest}:#{Float.round(lat * 1.0, 4)},#{Float.round(lon * 1.0, 4)},r=#{radius},l=#{limit}"
  end

  def format(data, lat, lon) do
    {p, coords} = Suggestions.fields(data)
    [longitude, latitude] = coords || [lon, lat]
    street = [p["street"], p["housenumber"]] |> Enum.reject(&is_nil/1) |> Enum.join(" ")
    name = p["name"] || if(street == "", do: p["city"] || "Unknown Place", else: street)

    %{
      "id" => nil,
      "name" => name,
      "latitude" => latitude,
      "longitude" => longitude,
      "osm_id" => p["osm_id"],
      "osm_type" => p["osm_type"],
      "osm_key" => p["osm_key"],
      "osm_value" => p["osm_value"],
      "city" => p["city"],
      "country" => p["country"],
      "street" => p["street"],
      "housenumber" => p["housenumber"],
      "postcode" => p["postcode"],
      "source" => "photon",
      "geodata" => data
    }
  end

  def saved(owner, lat, lon, radius, limit, query) do
    rows =
      Repo.query!(
        "SELECT p.id,p.name,ST_Y(p.lonlat::geometry),ST_X(p.lonlat::geometry),p.source FROM places p WHERE p.user_id=$1 AND p.lonlat IS NOT NULL AND (p.source IN (0,2) OR EXISTS (SELECT 1 FROM taggings g WHERE g.taggable_type='Place' AND g.taggable_id=p.id) OR EXISTS (SELECT 1 FROM visits v WHERE v.place_id=p.id AND v.user_id=$1 AND v.status=1 AND v.deleted_at IS NULL)) ORDER BY p.id",
        [owner]
      ).rows

    rows
    |> Enum.map(fn [id, name, latitude, longitude, source] ->
      %{
        "id" => id,
        "name" => name,
        "latitude" => latitude,
        "longitude" => longitude,
        "source" => %{0 => "manual", 1 => "photon", 2 => "gpx_waypoint"}[source]
      }
    end)
    |> Enum.filter(fn place ->
      if String.length(query) >= 2,
        do: String.contains?(String.downcase(place["name"] || ""), String.downcase(query)),
        else: distance(place, lat, lon) <= radius
    end)
    |> Enum.sort_by(&distance(&1, lat, lon))
    |> Enum.take(limit)
  end

  def distance(%{"latitude" => lat, "longitude" => lon}, latitude, longitude)
      when is_number(lat) and is_number(lon),
      do: Geo.distance_m({lat, lon}, {latitude, longitude}) / 1000

  def distance(_, _, _), do: :infinity
  def number(nil, default), do: default
  def number(value, _), do: Ruby.to_f(value)
  def count(nil, default), do: default
  def count(value, _), do: Ruby.to_i(value)
end

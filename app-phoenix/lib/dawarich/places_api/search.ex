defmodule Dawarich.PlacesApi.Search do
  @moduledoc false
  alias Dawarich.{I18n, Repo}
  alias Dawarich.Ingest.Ruby
  alias Dawarich.Locations.Suggestions
  alias Dawarich.PlacesApi.{Nearby, Payload}

  def run(user, params) do
    cond do
      not Ruby.present?(params["lat"]) or not Ruby.present?(params["lon"]) ->
        error("lat_and_lon_are_required")

      true ->
        lat = Ruby.to_f(params["lat"])
        lon = Ruby.to_f(params["lon"])

        if abs(lat) > 90 or abs(lon) > 180 do
          error("invalid_coordinates")
        else
          radius = Nearby.number(params["radius"], 1.0) |> max(0.01) |> min(5.0)
          limit = Nearby.count(params["limit"], 10) |> max(1) |> min(50)
          query = params["q"] |> Ruby.to_s() |> String.trim()
          saved = Nearby.saved(user.id, lat, lon, radius, limit, query)
          external = external(user, query, lat, lon, radius, limit)

          places =
            (saved ++ Enum.reject(external, &co_located_saved_place?(&1, saved)))
            |> Enum.sort_by(&Nearby.distance(&1, lat, lon))
            |> Enum.take(limit)

          {:ok, 200, %{"places" => places, "areas" => areas(user.id, lat, lon, radius, query)}}
        end
    end
  rescue
    _ -> {:ok, 500, %{"error" => "Internal Server Error"}}
  end

  defp external(user, query, lat, lon, radius, limit) do
    if String.length(query) < 2 do
      Nearby.fetch(user, lat, lon, radius, limit, cache: true)
    else
      opts = [
        limit: 50,
        bias: {lat, lon},
        params: bounds(Suggestions.configuration(), lat, lon, radius)
      ]

      (Suggestions.lookup(user, String.slice(query, 0, 200), opts) || [])
      |> Enum.map(&Nearby.format(&1, lat, lon))
      |> Enum.filter(&(Nearby.distance(&1, lat, lon) <= radius))
      |> Enum.sort_by(&Nearby.distance(&1, lat, lon))
      |> Enum.take(limit)
    end
  end

  defp bounds(_config, lat, _lon, _radius) when abs(lat) >= 89, do: %{}

  defp bounds(config, lat, lon, radius) do
    delta_lat = radius / 6371 * 180 / :math.pi()
    delta_lon = delta_lat / :math.cos(lat * :math.pi() / 180)

    if lon - delta_lon < -180 or lon + delta_lon > 180 do
      %{}
    else
      [minlat, minlon, maxlat, maxlon] =
        Enum.map(
          [max(lat - delta_lat, -90), lon - delta_lon, min(lat + delta_lat, 90), lon + delta_lon],
          &Float.round(&1, 6)
        )

      case config[:provider] do
        p when p in [:nominatim, :locationiq] ->
          %{"viewbox" => "#{minlon},#{maxlat},#{maxlon},#{minlat}", "bounded" => "1"}

        :geoapify ->
          %{"filter" => "rect:#{minlon},#{minlat},#{maxlon},#{maxlat}"}

        _ ->
          %{"bbox" => "#{minlon},#{minlat},#{maxlon},#{maxlat}"}
      end
    end
  end

  def co_located_saved_place?(external, saved) do
    Enum.any?(saved, fn place ->
      String.downcase(String.trim(place["name"] || "")) ==
        String.downcase(String.trim(external["name"] || "")) and
        Nearby.distance(external, place["latitude"], place["longitude"]) <= 0.05
    end)
  end

  defp areas(owner, lat, lon, radius, query) do
    Repo.query!(
      "SELECT id,name,latitude::float8,longitude::float8,radius FROM areas WHERE user_id=$1",
      [owner]
    ).rows
    |> Enum.map(fn [id, name, latitude, longitude, r] ->
      %{
        "id" => id,
        "name" => name,
        "latitude" => latitude,
        "longitude" => longitude,
        "radius" => r,
        "source" => "area"
      }
    end)
    |> Enum.filter(fn area ->
      Nearby.distance(area, lat, lon) <= radius or
        (String.length(query) >= 2 and
           String.contains?(String.downcase(area["name"] || ""), String.downcase(query)))
    end)
    |> Enum.sort_by(&Nearby.distance(&1, lat, lon))
    |> Enum.take(10)
  end

  def index(owner, params) do
    confirmed =
      "p.id IN (SELECT place_id FROM visits WHERE user_id=$1 AND deleted_at IS NULL AND status=1 AND place_id IS NOT NULL)"

    tagged =
      "EXISTS (SELECT 1 FROM taggings g WHERE g.taggable_type='Place' AND g.taggable_id=p.id)"

    where =
      case params["filter"] do
        "all" -> "TRUE"
        "manual" -> "p.source=0"
        "confirmed" -> confirmed
        "tagged" -> tagged
        _ -> "(p.source IN (0,2) OR #{confirmed} OR #{tagged})"
      end

    where = where <> tags(params["tag_ids"], tagged)

    [[total]] =
      Repo.query!("SELECT count(*) FROM places p WHERE p.user_id=$1 AND " <> where, [owner]).rows

    page = if Ruby.present?(params["page"]), do: max(Ruby.to_i(params["page"]), 1), else: nil
    per = min(Nearby.count(params["per_page"], 100), 500)
    if page && per <= 0, do: raise(ArgumentError)
    tail = if page, do: " LIMIT #{per} OFFSET #{(page - 1) * per}", else: ""
    rows = Payload.places(owner, where, [], tail)

    headers = [
      {"x-current-page", to_string(page || 1)},
      {"x-total-pages", to_string(if(page, do: div(total + per - 1, per), else: 1))},
      {"x-total-count", to_string(total)}
    ]

    {:ok, 200, rows, headers}
  end

  defp tags(value, tagged) do
    ids = if is_list(value), do: value, else: if(Ruby.present?(value), do: [value], else: [])
    numbers = for value <- ids, value != "untagged", do: Ruby.to_i(value)

    clauses =
      if numbers == [],
        do: [],
        else: [
          "EXISTS (SELECT 1 FROM taggings g WHERE g.taggable_type='Place' AND g.taggable_id=p.id AND g.tag_id IN (#{Enum.join(numbers, ",")}))"
        ]

    clauses = if "untagged" in ids, do: clauses ++ ["NOT (#{tagged})"], else: clauses
    if clauses == [], do: "", else: " AND (#{Enum.join(clauses, " OR ")})"
  end

  defp error(key), do: {:ok, 400, %{"error" => I18n.en!("controllers.api.v1.places." <> key)}}
end

defmodule Dawarich.Locations.Suggestions do
  @moduledoc false
  alias Dawarich.{Geo, I18n, Redis, Repo}
  alias Dawarich.Geocoding.{Config, Http, Query, RateLimiter, ResponseCache, Search}
  alias Dawarich.Ingest.Ruby

  def term(%{"suggestions" => list}),
    do:
      {:object,
       [
         {"suggestions",
          Enum.map(
            list,
            &{:object, Enum.map(~w(name address coordinates type), fn key -> {key, &1[key]} end)}
          )}
       ]}

  def term(other), do: other

  def run(_user, %{"q" => q}) when not is_nil(q) and not is_binary(q),
    do: {:ok, 500, %{"error" => "Internal Server Error"}}

  def run(user, params) do
    query = String.trim(params["q"] || "")

    cond do
      String.length(query) > 200 ->
        {:ok, 400,
         %{
           "error" =>
             I18n.en!("controllers.api.v1.locations.search_query_too_long_max_200_characters")
         }}

      String.length(query) < 2 ->
        {:ok, 200, %{"suggestions" => []}}

      true ->
        config = configuration(true)
        results = lookup(user, query, limit: 10, fallback: true)

        suggestions =
          Enum.reduce(results || [], [], fn data, acc ->
            {p, coords} = fields(data)
            [lon, lat] = coords || [0.0, 0.0]
            address = address(config.provider, data, p)

            item = %{
              "name" =>
                if(address == "",
                  do: "Unknown location",
                  else: List.first(String.split(address, ","))
                ),
              "address" => address,
              "coordinates" => [lat, lon],
              "type" => data["type"] || data["class"] || "unknown"
            }

            if abs(lat) <= 90 and abs(lon) <= 180 and
                 not Enum.any?(
                   acc,
                   &(Geo.distance_m({lat, lon}, List.to_tuple(&1["coordinates"])) < 100)
                 ),
               do: acc ++ [item],
               else: acc
          end)

        {:ok, 200, %{"suggestions" => suggestions}}
    end
  rescue
    _ -> {:ok, 200, %{"suggestions" => []}}
  end

  def configuration(fallback \\ false) do
    case Config.resolve(Repo) do
      %{enabled: false} = config when not fallback ->
        config

      %{enabled: false} ->
        %{
          enabled: true,
          source: :fallback,
          provider: :nominatim,
          host: "nominatim.openstreetmap.org",
          api_key: nil,
          use_https: true,
          rps: 1.0
        }

      config ->
        config
    end
  end

  def lookup(user, query, opts \\ []) do
    config = configuration(opts[:fallback] || false)
    if config.enabled, do: throttle(config, fn -> search(config, user, query, opts) end), else: []
  rescue
    _ -> []
  end

  defp throttle(%{rps: rps}, fun) when is_nil(rps) or rps <= 0, do: fun.()

  defp throttle(config, fun) do
    interval = round(1_000_000 / config.rps)

    case Redis.command([
           "EVAL",
           RateLimiter.lua(),
           "1",
           "geocoding:rate_limit:" <> RateLimiter.key(config),
           to_string(interval),
           "1000000"
         ]) do
      {:ok, -1} ->
        nil

      {:ok, wait} ->
        if wait > 0, do: Process.sleep(div(wait + 999, 1000))
        fun.()

      _ ->
        nil
    end
  end

  defp search(config, _user, {lat, lon}, opts) do
    case Search.reverse(%{config | rps: nil}, {lat, lon}, opts) do
      {:ok, results} -> results
      _ -> []
    end
  end

  defp search(config, _user, query, opts) do
    {url, key, headers} = forward(config, query, opts)

    response =
      case ResponseCache.get(key) do
        {:ok, body} -> {:ok, 200, body}
        _ -> Http.get(url, headers)
      end

    with {:ok, status, body} when status in 200..399 <- response,
         {:ok, doc} <- Dawarich.Photos.ProviderCache.decode_json(body) do
      ResponseCache.put(key, body)

      case config.provider do
        p when p in [:photon, :geoapify] ->
          if doc["type"] == "FeatureCollection", do: doc["features"] || [], else: []

        _ ->
          if is_list(doc), do: doc, else: [doc]
      end
    else
      _ -> []
    end
  end

  defp forward(config, query, opts) do
    version = Dawarich.RailsRoot.join(".app_version") |> File.read!() |> String.trim()
    {url, _, headers} = Query.build(config, {0.0, 0.0}, opts, version)
    uri = URI.parse(url)
    params = URI.decode_query(uri.query) |> Map.drop(~w(lat lon radius distance_sort))

    path =
      if config.provider == :photon,
        do: "/api",
        else: String.replace(uri.path, "reverse", "search")

    field = if config.provider == :geoapify, do: "text", else: "q"
    params = params |> Map.put(field, query) |> Map.merge(opts[:params] || %{})

    params =
      if config.provider == :photon and opts[:bias],
        do:
          Map.merge(params, %{
            "lat" => to_string(elem(opts[:bias], 0)),
            "lon" => to_string(elem(opts[:bias], 1))
          }),
        else: params

    encoded = fn map -> map |> Enum.sort() |> URI.encode_query() end
    key_params = Map.drop(params, ~w(apiKey key))

    {URI.to_string(%{uri | path: path, query: encoded.(params)}),
     URI.to_string(%{uri | path: path, query: encoded.(key_params)}), headers}
  end

  def fields(%{"properties" => p} = data) when is_map(p) do
    ds = p["datasource"] || %{}

    props =
      p
      |> Map.put("osm_id", p["osm_id"] || ds["osm_id"])
      |> Map.put("osm_type", p["osm_type"] || ds["osm_type"])
      |> Map.put("osm_key", p["osm_key"] || p["category"])
      |> Map.put("osm_value", p["osm_value"] || p["result_type"] || p["type"])

    coords =
      get_in(data, ["geometry", "coordinates"]) ||
        if(p["lon"] && p["lat"], do: [Ruby.to_f(p["lon"]), Ruby.to_f(p["lat"])])

    {props, coords}
  end

  def fields(data) when is_map(data) do
    a = data["address"] || %{}

    props = %{
      "name" => data["name"],
      "street" => a["road"] || a["pedestrian"] || a["highway"] || a["footway"],
      "housenumber" => a["house_number"],
      "city" => a["city"] || a["town"] || a["village"] || a["hamlet"] || a["municipality"],
      "country" => a["country"],
      "postcode" => a["postcode"],
      "osm_id" => data["osm_id"],
      "osm_type" => data["osm_type"],
      "osm_key" => data["category"] || data["class"],
      "osm_value" => data["type"] || data["addresstype"]
    }

    coords =
      if Ruby.present?(data["lon"]) and Ruby.present?(data["lat"]),
        do: [Ruby.to_f(data["lon"]), Ruby.to_f(data["lat"])]

    {props, coords}
  end

  def fields(_), do: {%{}, nil}

  defp address(:photon, _data, p) do
    street =
      if p["street"],
        do: if(p["housenumber"], do: "#{p["housenumber"]} #{p["street"]}", else: p["street"])

    Enum.join(
      Enum.reject([p["name"], street], &is_nil/1) ++
        [p["city"]] ++ Enum.reject([p["state"]], &is_nil/1) ++ [p["postcode"], p["country"]],
      ", "
    )
  end

  defp address(:geoapify, _data, p), do: p["formatted"] || ""
  defp address(_, data, _p), do: data["display_name"] || ""
end

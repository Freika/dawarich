defmodule Dawarich.Photos.Index do
  @moduledoc false
  alias Dawarich.Accounts
  alias Dawarich.Photos.{ProviderCache, Thumbnail}
  alias Dawarich.Imports.ImportTime
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  defdelegate term(photos), to: ProviderCache

  def fetch(user, params, opts \\ []) do
    settings = Keyword.get_lazy(opts, :settings, fn -> Accounts.settings(user.id) end)
    settings = Dawarich.UserSettings.get(%{settings: settings})
    key = ProviderCache.key(user.id, params["start_date"], params["end_date"])

    if Thumbnail.configured?(settings || %{}) do
      case ProviderCache.get(key) do
        {:ok, photos} when is_list(photos) and photos != [] -> {:ok, photos, []}
        _ -> search(user, settings, params, key)
      end
    else
      {:unconfigured, params["source"]}
    end
  rescue
    _ -> {:error, 502}
  end

  def cached(user, opts \\ []) do
    params = %{
      "start_date" => Keyword.get(opts, :start_date, "1970-01-01"),
      "end_date" => opts[:end_date]
    }

    key = "photos_search/#{user.id}/v2/#{params["start_date"]}/#{params["end_date"]}"

    case ProviderCache.get(key) do
      {:ok, photos} when is_list(photos) and photos != [] ->
        photos

      _ ->
        case fetch(user, params) do
          {:ok, photos, _} ->
            if photos != [],
              do: ProviderCache.put(key, photos, Keyword.get(opts, :expires_in, 60))

            photos

          _ ->
            []
        end
    end
  end

  defp search(user, settings, params, key) do
    results =
      for source <- ~w(immich photoprism),
          configured?(settings, source),
          do: {source, assets(settings, source, params, user.id)}

    errors = for {source, {:error, _}} <- results, do: source

    if results != [] and length(errors) == length(results) do
      {:error, 502}
    else
      photos =
        for {source, {:ok, assets}} <- results,
            asset <- assets,
            String.downcase(asset["type"] || asset["Type"]) != "video",
            do: serialize(asset, source)

      if photos != [] and errors == [], do: ProviderCache.put(key, photos)
      {:ok, photos, errors}
    end
  end

  def assets(settings, "immich", params, _user) do
    immich(settings, params, 1, [])
  rescue
    _ -> {:error, :invalid}
  end

  def assets(settings, "photoprism", params, user) do
    photoprism(settings, params, user, 0, [])
  rescue
    _ -> {:error, :invalid}
  end

  defp immich(_settings, params, page, acc) when page > 10_000,
    do: {:ok, framed(acc, "immich", params)}

  defp immich(settings, params, page, acc) do
    body = %{
      "takenAfter" => normalized(params["start_date"], false),
      "size" => 1000,
      "page" => page,
      "order" => "asc",
      "withExif" => true,
      "isArchived" => false,
      "visibility" => "timeline"
    }

    body =
      if params["end_date"],
        do: Map.put(body, "takenBefore", normalized(params["end_date"], true)),
        else: body

    with {:ok, status, response_headers, raw} <-
           request(
             :post,
             settings["immich_url"],
             "/api/search/metadata",
             headers(settings, "immich"),
             Jason.encode!(body),
             settings["immich_skip_ssl_verification"]
           ),
         true <- status in 200..299 and json?(response_headers),
         {:ok, doc} <- Jason.decode(raw),
         items when is_list(items) <- get_in(doc, ["assets", "items"]) do
      if items == [],
        do: {:ok, framed(acc, "immich", params)},
        else:
          immich(
            settings,
            params,
            page + 1,
            acc ++
              Enum.reject(items, &(&1["isArchived"] == true or &1["visibility"] == "archive"))
          )
    else
      _ -> {:error, :provider}
    end
  end

  defp photoprism(_settings, params, _user, offset, acc) when offset >= 1_000_000,
    do: {:ok, framed(acc, "photoprism", params)}

  defp photoprism(settings, params, user, offset, acc) do
    from = if Ruby.present?(params["start_date"]), do: params["start_date"], else: "1970-01-01"

    query = %{
      "q" => "",
      "public" => "true",
      "quality" => 3,
      "after" => utc_date(from),
      "count" => 1000
    }

    query = if offset > 0, do: Map.put(query, "offset", offset), else: query

    query =
      if Ruby.present?(params["end_date"]),
        do: Map.put(query, "before", utc_date(params["end_date"], 1)),
        else: query

    path = "/api/v1/photos?" <> URI.encode_query(query)

    with {:ok, status, response_headers, raw} <-
           request(
             :get,
             settings["photoprism_url"],
             path,
             headers(settings, "photoprism"),
             nil,
             settings["photoprism_skip_ssl_verification"]
           ),
         true <- status in 200..299 and json?(response_headers),
         {:ok, items} when is_list(items) <- Jason.decode(raw) do
      token =
        Enum.find_value(response_headers, fn {k, v} ->
          if String.downcase(to_string(k)) == "x-preview-token", do: to_string(v)
        end)

      ProviderCache.put_token(user, token)

      if items == [],
        do: {:ok, framed(acc, "photoprism", Map.put(params, "start_date", from))},
        else: photoprism(settings, params, user, offset + 1000, acc ++ items)
    else
      _ -> {:error, :provider}
    end
  end

  defp json?(headers),
    do:
      Enum.any?(headers, fn {k, v} ->
        String.downcase(to_string(k)) == "content-type" and
          String.contains?(to_string(v), "application/json")
      end)

  defdelegate request(method, base, path, headers, body, skip),
    to: Dawarich.Photos.ProviderHTTP

  defp headers(s, "immich"),
    do: [{"x-api-key", s["immich_api_key"]}, {"accept", "application/json"}]

  defp headers(s, "photoprism"),
    do: [{"authorization", "Bearer #{s["photoprism_api_key"]}"}, {"accept", "application/json"}]

  defp configured?(s, source),
    do: Ruby.present?(s[source <> "_url"]) and Ruby.present?(s[source <> "_api_key"])

  def parse(value, end_day \\ false) do
    if Ruby.present?(value) do
      zone =
        if end_day and date_only?(value),
          do: System.get_env("TIME_ZONE", "Europe/Berlin"),
          else: "Etc/UTC"

      time = ImportTime.parse(to_string(value), zone, DateTime.utc_now())
      if time && end_day && date_only?(value), do: time + 86399, else: time
    end
  rescue
    _ -> nil
  end

  defp date_only?(s), do: is_binary(s) and Regex.match?(~r/\A\d{4}-\d{2}-\d{2}\z/, s)

  defp normalized(value, end_day),
    do:
      if(time = parse(value, end_day),
        do: DateTime.from_unix!(time) |> DateTime.to_iso8601(),
        else: value
      )

  defp utc_date(value, shift \\ 0),
    do:
      DateTime.from_unix!(parse(value))
      |> DateTime.to_date()
      |> Date.add(shift)
      |> Date.to_iso8601()

  defp framed(assets, source, params) do
    from = parse(params["start_date"])

    to =
      if(source == "photoprism" and date_only?(params["end_date"]),
        do: parse(params["end_date"]) + 86399,
        else: parse(params["end_date"], true)
      )

    to = to || if(source == "photoprism", do: System.system_time(:second))

    if is_nil(from) and source == "immich" do
      assets
    else
      Enum.filter(assets, fn asset ->
        ts =
          if source == "immich",
            do: asset["fileCreatedAt"] || asset["localDateTime"],
            else: asset["TakenAt"] || asset["TakenAtLocal"]

        time = parse(ts)
        time && time >= from && (is_nil(to) || time <= to)
      end)
    end
  end

  def serialize(photo, source) do
    exif = photo["exifInfo"] || %{}

    %{
      "id" => photo["id"] || photo["Hash"],
      "latitude" => exif["latitude"] || photo["Lat"],
      "longitude" => exif["longitude"] || photo["Lng"],
      "localDateTime" =>
        if(source == "immich", do: photo["localDateTime"], else: photo["TakenAtLocal"]),
      "capturedAt" => if(source == "immich", do: photo["fileCreatedAt"], else: photo["TakenAt"]),
      "originalFileName" => photo["originalFileName"] || photo["OriginalName"],
      "city" => exif["city"] || photo["PlaceCity"],
      "state" => exif["state"] || photo["PlaceState"],
      "country" => exif["country"] || photo["PlaceCountry"],
      "type" => String.downcase(photo["type"] || photo["Type"]),
      "orientation" =>
        if(
          (source == "immich" and exif["orientation"] == "6") or
            (source == "photoprism" and photo["Portrait"] not in [nil, false]),
          do: "portrait",
          else: "landscape"
        ),
      "source" => source
    }
  end
end

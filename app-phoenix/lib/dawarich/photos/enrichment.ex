defmodule Dawarich.Photos.Enrichment do
  @moduledoc false
  alias Dawarich.{Accounts, Entitlements, I18n, Notifications, ReleaseMigration, Repo}
  alias Dawarich.Photos.Index
  alias Dawarich.Ingest.Ruby

  def term(list) when is_list(list), do: Enum.map(list, &term/1)

  def term(map) when is_map(map) do
    keys =
      cond do
        Map.has_key?(map, "matches") ->
          ~w(error matches total_without_geodata total_matched)

        Map.has_key?(map, "enriched") ->
          ~w(error enriched pending failed errors)

        Map.has_key?(map, "immich_asset_id") ->
          ~w(immich_asset_id filename photo_timestamp time_delta_seconds latitude longitude match_method error)

        true ->
          Map.keys(map)
      end

    {:object, for(key <- keys, Map.has_key?(map, key), do: {key, term(map[key])})}
  end

  def term(other), do: other

  def pro?(user, now), do: Entitlements.full_access?(user, ReleaseMigration.self_hosted?(), now)

  def run(action, user, params, opts \\ []) do
    settings = Accounts.settings(user.id) || %{}

    case missing(settings) do
      nil -> dispatch(action, user, params, settings, opts)
      message -> {:ok, 200, error_result(action, message)}
    end
  rescue
    _ -> {:error, 500}
  end

  defp missing(settings) do
    cond do
      Ruby.blank?(settings["immich_url"]) ->
        I18n.en!("services.immich.configuration.url_missing")

      Ruby.blank?(settings["immich_api_key"]) ->
        I18n.en!("services.immich.configuration.api_key_missing")

      true ->
        nil
    end
  end

  defp dispatch(:scan, user, params, settings, _opts) do
    params = Map.put(params, "start_date", params["start_date"] || "1970-01-01")

    case Index.assets(settings, "immich", params, user.id) do
      {:ok, photos} ->
        photos =
          Enum.reject(photos, fn p ->
            e = p["exifInfo"] || %{}

            Ruby.present?(e["latitude"]) and e["latitude"] != 0 and Ruby.present?(e["longitude"]) and
              e["longitude"] != 0
          end)

        tolerance = Ruby.to_i(params["tolerance"] || 1800)

        points =
          Repo.query!(
            "SELECT timestamp,ST_Y(lonlat::geometry),ST_X(lonlat::geometry) FROM points WHERE user_id=$1 AND timestamp IS NOT NULL AND lonlat IS NOT NULL ORDER BY timestamp",
            [user.id]
          ).rows

        matches = Enum.flat_map(photos, &match(&1, points, tolerance))

        {:ok, 200,
         %{
           "matches" => matches,
           "total_without_geodata" => length(photos),
           "total_matched" => length(matches)
         }}

      _ ->
        {:ok, 200,
         error_result(
           :scan,
           I18n.en!("services.immich.enrich_scan.failed_to_fetch_photos_from_immich")
         )}
    end
  end

  defp dispatch(:create, user, params, settings, opts) do
    assets =
      Enum.map(params["assets"] || [], &Map.take(&1, ~w(immich_asset_id latitude longitude)))

    enqueue =
      Keyword.get(
        opts,
        :enqueue,
        Application.get_env(
          :dawarich,
          :immich_verification_enqueue,
          &Dawarich.Immich.Enrichment.enqueue/4
        )
      )

    if assets != [] and not is_function(enqueue, 4) do
      {:error, :verification_unavailable}
    else
      {submitted, errors} =
        Enum.reduce(assets, {[], []}, fn asset, {submitted, errors} ->
          case update(settings, asset) do
            :ok ->
              {submitted ++ [asset], errors}

            {:error, message} ->
              {submitted,
               errors ++ [%{"immich_asset_id" => asset["immich_asset_id"], "error" => message}]}
          end
        end)

      if submitted != [] do
        now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)

        {:ok, content} =
          I18n.t("en", "services.immich.enrich_photos.checking", %{"count" => length(submitted)})

        id =
          Notifications.create!(
            Repo,
            user.id,
            :info,
            I18n.en!("services.immich.enrich_photos.checking_title"),
            content,
            DateTime.to_naive(now)
          )

        :ok = enqueue.(id, submitted, settings["immich_url"], DateTime.add(now, 10))
      end

      {:ok, 200,
       %{
         "enriched" => 0,
         "pending" => length(submitted),
         "failed" => length(errors),
         "errors" => errors
       }}
    end
  end

  defp update(settings, asset) do
    id = URI.encode(to_string(asset["immich_asset_id"]), &URI.char_unreserved?/1)
    headers = [{"x-api-key", settings["immich_api_key"]}, {"accept", "application/json"}]

    case Index.request(
           :put,
           settings["immich_url"],
           "/api/assets/" <> id,
           headers,
           Jason.encode!(Map.take(asset, ~w(latitude longitude))),
           settings["immich_skip_ssl_verification"]
         ) do
      {:ok, status, _, _} when status in 200..299 ->
        :ok

      {:ok, status, _, _} ->
        {:error, "HTTP #{status}: #{reason(status)}"}

      {:error, reason} ->
        {:error, transport_message(reason)}
    end
  end

  defp reason(400), do: "Bad Request"
  defp reason(401), do: "Unauthorized"
  defp reason(403), do: "Forbidden"
  defp reason(404), do: "Not Found"
  defp reason(422), do: "Unprocessable Entity"
  defp reason(429), do: "Too Many Requests"
  defp reason(500), do: "Internal Server Error"
  defp reason(502), do: "Bad Gateway"
  defp reason(503), do: "Service Unavailable"
  defp reason(_), do: ""
  defp transport_message(:timeout), do: "Net::ReadTimeout with #<Socket:(closed)>"
  defp transport_message(_), do: "Failed to open TCP connection"

  defp match(photo, points, tolerance) do
    ts =
      Index.parse(
        photo["fileCreatedAt"] || get_in(photo, ["exifInfo", "dateTimeOriginal"]) ||
          photo["localDateTime"]
      )

    if ts do
      before = points |> Enum.take_while(&(hd(&1) <= ts)) |> List.last()
      after_point = Enum.find(points, &(hd(&1) > ts))
      coordinates = coordinates(before, after_point, ts, tolerance)

      case coordinates do
        {lat, lon, delta, method} ->
          [
            %{
              "immich_asset_id" => photo["id"],
              "filename" => photo["originalFileName"],
              "photo_timestamp" => DateTime.from_unix!(ts) |> DateTime.to_iso8601(),
              "time_delta_seconds" => delta,
              "latitude" => Float.round(lat, 6),
              "longitude" => Float.round(lon, 6),
              "match_method" => method
            }
          ]

        nil ->
          []
      end
    else
      []
    end
  end

  defp coordinates([bt, blat, blon], [at, alat, alon], ts, tolerance)
       when at - bt <= tolerance and ts - bt <= tolerance and at - ts <= tolerance do
    fraction = (ts - bt) / (at - bt)
    {lat, lon} = interpolate({blat, blon}, {alat, alon}, fraction)
    {lat, lon, if(fraction <= 0.5, do: ts - bt, else: at - ts), "interpolated"}
  end

  defp coordinates(before, after_point, ts, tolerance) do
    case Enum.reject([before, after_point], &is_nil/1)
         |> Enum.filter(&(abs(hd(&1) - ts) <= tolerance))
         |> Enum.min_by(&abs(hd(&1) - ts), fn -> nil end) do
      [at, lat, lon] -> {lat, lon, abs(at - ts), "nearest"}
      nil -> nil
    end
  end

  defp interpolate({lat1, lon1}, {lat2, lon2}, fraction) do
    from = vector(lat1, lon1)
    to = vector(lat2, lon2)

    angle =
      :math.acos(
        Enum.zip(from, to)
        |> Enum.map(fn {a, b} -> a * b end)
        |> Enum.sum()
        |> max(-1.0)
        |> min(1.0)
      )

    sine = :math.sin(angle)

    cond do
      abs(angle) < 2.220446049250313e-16 ->
        {lat1, lon1}

      abs(sine) < 2.220446049250313e-16 ->
        {lat1 + (lat2 - lat1) * fraction, lon1 + (lon2 - lon1) * fraction}

      true ->
        a = :math.sin((1 - fraction) * angle) / sine
        b = :math.sin(fraction * angle) / sine
        [x, y, z] = Enum.zip(from, to) |> Enum.map(fn {left, right} -> a * left + b * right end)

        {:math.atan2(z, :math.sqrt(x * x + y * y)) * 180 / :math.pi(),
         :math.atan2(y, x) * 180 / :math.pi()}
    end
  end

  defp vector(lat, lon) do
    lat = lat * :math.pi() / 180
    lon = lon * :math.pi() / 180
    [:math.cos(lat) * :math.cos(lon), :math.cos(lat) * :math.sin(lon), :math.sin(lat)]
  end

  defp error_result(:scan, message),
    do: %{"error" => message, "matches" => [], "total_without_geodata" => 0, "total_matched" => 0}

  defp error_result(:create, message),
    do: %{"error" => message, "enriched" => 0, "pending" => 0, "failed" => 0, "errors" => []}
end

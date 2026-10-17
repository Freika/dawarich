defmodule Dawarich.Imports.Integrations.Immich do
  @moduledoc false
  alias Dawarich.Imports.Integrations.PhotoImportRecord

  def run(repo, args, opts \\ []),
    do: PhotoImportRecord.run(repo, args, "immich", 5, &fetch(&1, &2, args["time_zone"]), opts)

  def classify({:error, _}), do: {:error, :connection}
  def classify({:ok, status, _}) when status not in 200..299, do: {:ok, []}

  def classify({:ok, _, body}) do
    case Jason.decode(body) do
      {:ok, %{"assets" => %{"items" => items}}} when is_list(items) -> {:ok, items}
      {:ok, _} -> {:ok, []}
      _ -> {:discard, :invalid_payload}
    end
  end

  defp fetch(settings, current, zone) do
    rules = Dawarich.Imports.ZonePeriod.load!(Dawarich.TimeZoneName.to_iana(zone))
    start = Dawarich.Imports.ZonePeriod.resolve(rules, ~N[1970-01-01 00:00:00])
    pages(settings |> Map.put("start", start) |> Map.put("zone", zone), current, 1, [])
  end

  defp pages(_settings, _current, page, rows) when page > 10_000,
    do: geodata(Enum.reverse(rows) |> List.flatten())

  defp pages(settings, current, page, rows) do
    if current.() do
      case request(settings, page) |> classify() do
        {:ok, []} ->
          geodata(Enum.reverse(rows) |> List.flatten())

        {:ok, items} ->
          filtered =
            Enum.filter(items, fn asset ->
              frame = asset["fileCreatedAt"] || asset["localDateTime"]

              if is_binary(frame) do
                stamp =
                  Dawarich.Imports.ImportTime.parse(frame, settings["zone"], DateTime.utc_now())

                not is_nil(stamp) and stamp >= settings["start"]
              else
                false
              end
            end)

          pages(settings, current, page + 1, [filtered | rows])

        error ->
          error
      end
    else
      {:cancel, :ownership_lost}
    end
  rescue
    _ in [ArgumentError, BadMapError, FunctionClauseError] -> {:discard, :invalid_payload}
  end

  defp request(settings, page) do
    url = settings["immich_url"]
    key = settings["immich_api_key"]

    if not is_binary(url) or url == "" or not is_binary(key) or key == "" do
      {:ok, 400, ""}
    else
      body =
        Jason.encode!(%{
          takenAfter: settings["start"] |> DateTime.from_unix!() |> DateTime.to_iso8601(),
          size: 1000,
          page: page,
          order: "asc",
          withExif: true,
          isArchived: false,
          visibility: "timeline"
        })

      headers = [{~c"x-api-key", String.to_charlist(key)}, {~c"accept", ~c"application/json"}]

      case Dawarich.Photos.ProviderHTTP.request(
             :post,
             url,
             "/api/search/metadata",
             headers,
             body,
             settings["immich_skip_ssl_verification"]
           ) do
        {:ok, status, _, body} -> {:ok, status, body}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp geodata(assets) do
    result =
      Enum.reduce_while(
        Enum.reject(assets, &(&1["isArchived"] == true or &1["visibility"] == "archive")),
        {:ok, []},
        fn asset, {:ok, rows} ->
          lat = get_in(asset, ["exifInfo", "latitude"])
          lon = get_in(asset, ["exifInfo", "longitude"])
          time = asset["fileCreatedAt"] || get_in(asset, ["exifInfo", "dateTimeOriginal"])

          cond do
            lat in [nil, false, 0, 0.0] or lon in [nil, false, 0, 0.0] or is_nil(time) ->
              {:cont, {:ok, rows}}

            not is_number(lat) or not is_number(lon) or not is_binary(time) ->
              {:halt, {:discard, :invalid_payload}}

            true ->
              case DateTime.from_iso8601(time) do
                {:ok, stamp, _} -> {:cont, {:ok, [{lat, lon, DateTime.to_unix(stamp)} | rows]}}
                _ -> {:halt, {:discard, :invalid_payload}}
              end
          end
        end
      )

    case result do
      {:ok, rows} -> {:ok, Enum.reverse(rows) |> Enum.sort_by(&elem(&1, 2))}
      other -> other
    end
  rescue
    _ in [BadMapError, FunctionClauseError, ArgumentError] -> {:discard, :invalid_payload}
  end
end

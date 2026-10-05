defmodule Dawarich.Imports.Integrations.Photoprism do
  @moduledoc false
  alias Dawarich.Imports.Integrations.PhotoImportRecord

  def run(repo, args, opts \\ []),
    do: PhotoImportRecord.run(repo, args, "photoprism", 7, &fetch(repo, &1, &2, args), opts)

  def classify({:error, _}), do: {:error, :connection}
  def classify({:cancel, _} = error), do: error
  def classify({:ok, status, _, _}) when status not in 200..299, do: {:ok, []}

  def classify({:ok, _, type, body}) do
    if String.contains?(type, "application/json") do
      case Jason.decode(body) do
        {:ok, items} when is_list(items) -> {:ok, items}
        _ -> {:ok, []}
      end
    else
      {:ok, []}
    end
  end

  defp fetch(repo, settings, current, args) do
    if blank?(settings["photoprism_url"]) or blank?(settings["photoprism_api_key"]) do
      {:discard, :configuration_missing}
    else
      cache = fn token ->
        repo.transaction(fn ->
          if current.(), do: cache_token(args["user_id"], token), else: repo.rollback(:lost)
        end)
      end

      pages(settings, current, args["time_zone"], cache, 0, [])
    end
  end

  defp pages(_settings, _current, zone, _cache, offset, rows) when offset >= 1_000_000,
    do: geodata(Enum.reverse(rows) |> List.flatten(), zone)

  defp pages(settings, current, zone, cache, offset, rows) do
    if current.() do
      case request(settings, offset, cache) |> classify() do
        {:ok, []} -> geodata(Enum.reverse(rows) |> List.flatten(), zone)
        {:ok, items} -> pages(settings, current, zone, cache, offset + 1000, [items | rows])
        error -> error
      end
    else
      {:cancel, :ownership_lost}
    end
  end

  defp request(settings, offset, cache) do
    query = %{q: "", public: true, quality: 3, after: "1970-01-01", count: 1000}
    query = if offset == 0, do: query, else: Map.put(query, :offset, offset)
    url = settings["photoprism_url"] <> "/api/v1/photos?" <> URI.encode_query(query)

    headers = [
      {~c"authorization", String.to_charlist("Bearer " <> settings["photoprism_api_key"])},
      {~c"accept", ~c"application/json"},
      {~c"content-type", ~c"application/json"}
    ]

    ssl =
      if settings["photoprism_skip_ssl_verification"] == true,
        do: [verify: :verify_none],
        else: :httpc.ssl_verify_host_options(true)

    case :httpc.request(
           :get,
           {String.to_charlist(url), headers},
           [timeout: 10_000, connect_timeout: 10_000, autoredirect: false, ssl: ssl],
           body_format: :binary
         ) do
      {:ok, {{_, status, _}, headers, body}} ->
        type = headers |> List.keyfind(~c"content-type", 0, {nil, ~c""}) |> elem(1)

        if status in 200..299 and String.contains?(to_string(type), "application/json") and
             match?({:ok, _}, Jason.decode(body)) do
          token = headers |> List.keyfind(~c"x-preview-token", 0, {nil, nil}) |> elem(1)

          case cache.(if(token, do: to_string(token))) do
            {:ok, _} -> {:ok, status, to_string(type), body}
            {:error, :lost} -> {:cancel, :ownership_lost}
          end
        else
          {:ok, status, to_string(type), body}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp cache_token(user, token) do
    bytes =
      if is_nil(token),
        do: <<0, 17, 1, -1.0::little-float-64, -1::little-signed-32, 4, 8, 48>>,
        else: Dawarich.RailsCache.Wire.encode(token, expires_at: -1)

    Dawarich.Redis.cache_command(["SET", "dawarich/photoprism_preview_token_#{user}", bytes])
  end

  defp geodata(assets, zone) do
    now = DateTime.utc_now()
    assets = Enum.filter(assets, &in_frame?(&1, now))

    rows =
      Enum.reduce_while(assets, {:ok, []}, fn asset, {:ok, rows} ->
        lat = asset["Lat"]
        lon = asset["Lng"]

        cond do
          lat in [nil, false, 0, 0.0] or lon in [nil, false, 0, 0.0] or is_nil(asset["TakenAt"]) ->
            {:cont, {:ok, rows}}

          not is_number(lat) or not is_number(lon) ->
            {:halt, {:discard, :invalid_payload}}

          true ->
            stamp = Dawarich.Imports.ImportTime.parse(asset["TakenAt"], zone, now)

            if is_nil(stamp),
              do: {:halt, {:discard, :invalid_payload}},
              else: {:cont, {:ok, [{lat, lon, stamp} | rows]}}
        end
      end)

    case rows do
      {:ok, []} when assets != [] -> {:discard, :empty_geodata}
      {:ok, rows} -> {:ok, Enum.reverse(rows) |> Enum.sort_by(&elem(&1, 2))}
      other -> other
    end
  rescue
    _ in [BadMapError, FunctionClauseError, ArgumentError] -> {:discard, :invalid_payload}
  end

  defp in_frame?(asset, now) do
    frame = asset["TakenAt"] || asset["TakenAtLocal"]
    stamp = if is_binary(frame), do: Dawarich.Imports.ImportTime.parse(frame, "UTC", now)
    not is_nil(stamp) and stamp >= 0 and stamp <= DateTime.to_unix(now)
  rescue
    _ in [ArgumentError, BadMapError, FunctionClauseError] -> false
  end

  defp blank?(value), do: not is_binary(value) or String.trim(value) == ""
end

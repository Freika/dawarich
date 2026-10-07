defmodule Dawarich.MapApi.Hexagons do
  @moduledoc false
  alias Dawarich.{Repo, RailsTime}
  alias Dawarich.Tiles.Http
  alias Dawarich.MapApi.Hexagons.Boundary

  def fetch(user, params) do
    with {:ok, ctx} <- context(user, params) do
      case ctx.stat do
        nil ->
          {:ok, empty()}

        %{cells: cells} when is_list(cells) and cells != [] ->
          RailsTime.with_zone(ctx.user.timezone, fn ->
            features =
              Enum.with_index(cells, 1)
              |> Enum.map(fn {[index, count, earliest, latest], id} ->
                %{
                  "type" => "Feature",
                  "id" => id,
                  "geometry" => Boundary.polygon(index),
                  "properties" => %{
                    "hex_id" => id,
                    "point_count" => count,
                    "earliest_point" => time(earliest),
                    "latest_point" => time(latest)
                  }
                }
              end)

            {:ok,
             %{
               "type" => "FeatureCollection",
               "features" => features,
               "metadata" => %{
                 "count" => length(features),
                 "user_id" => ctx.user.id,
                 "pre_calculated" => true
               }
             }}
          end)

        _ ->
          {:ok, empty()}
      end
    end
  rescue
    _ -> {:error, 500, "Failed to generate hexagon grid"}
  end

  def bounds(user, params) do
    with {:ok, ctx} <- context(user, params),
         true <- Http.present?(ctx.from) and Http.present?(ctx.to),
         {:ok, range} <-
           RailsTime.with_zone(ctx.user.timezone, fn ->
             with {:ok, from} <- Http.strict_timestamp(ctx.from),
                  {:ok, to} <- Http.strict_timestamp(ctx.to),
                  do: {:ok, {from, to}}
           end) do
      {where, args} = Http.point_scope(ctx.user, if(ctx.shared, do: %{}, else: params), range)
      where = if ctx.shared, do: "p.user_id = $1 AND p.timestamp BETWEEN $2 AND $3", else: where
      args = if ctx.shared, do: [ctx.user.id, elem(range, 0), elem(range, 1)], else: args

      rows =
        if params["robust"] == "true",
          do: robust(where, args),
          else:
            Repo.query!(
              "SELECT COUNT(*),ST_YMin(ST_Extent(p.lonlat::geometry)),ST_YMax(ST_Extent(p.lonlat::geometry)),ST_XMin(ST_Extent(p.lonlat::geometry)),ST_XMax(ST_Extent(p.lonlat::geometry)) FROM points p WHERE #{where} AND (p.anomaly=false OR p.anomaly IS NULL)",
              args
            ).rows

      [[count, minlat, maxlat, minlng, maxlng]] = rows

      if count == 0,
        do: {:error, 404, "No data found for the specified date range"},
        else:
          {:ok,
           %{
             "point_count" => count,
             "min_lat" => minlat || 0.0,
             "max_lat" => maxlat || 0.0,
             "min_lng" => minlng || 0.0,
             "max_lng" => maxlng || 0.0
           }}
    else
      {:error, _, _} = error -> error
      _ -> {:error, 400, "No date range provided"}
    end
  rescue
    error ->
      if match?(%Postgrex.Error{postgres: %{code: :query_canceled}}, error),
        do: {:error, 503, "History bounds request timed out"},
        else: {:error, 400, "Invalid date format"}
  end

  defp robust(where, args) do
    sql =
      "SELECT FLOOR(ST_X(p.lonlat::geometry)/2)::int,FLOOR(ST_Y(p.lonlat::geometry)/2)::int,COUNT(*),MIN(ST_Y(p.lonlat::geometry)),MAX(ST_Y(p.lonlat::geometry)),MIN(ST_X(p.lonlat::geometry)),MAX(ST_X(p.lonlat::geometry)) FROM points p WHERE #{where} AND (p.anomaly=false OR p.anomaly IS NULL) AND p.lonlat IS NOT NULL GROUP BY 1,2"

    {:ok, cells} =
      Repo.transaction(fn ->
        Repo.query!("SET LOCAL statement_timeout = 5000")
        Repo.query!(sql, args).rows
      end)

    count = Enum.sum(Enum.map(cells, &Enum.at(&1, 2)))
    cells = if count < 50, do: cells, else: inliers(cells)

    if cells == [],
      do: [[0, nil, nil, nil, nil]],
      else: [[count, min_at(cells, 3), max_at(cells, 4), min_at(cells, 5), max_at(cells, 6)]]
  end

  defp inliers(cells) do
    keys = MapSet.new(cells, fn [x, y | _] -> {x, y} end)

    supported =
      Enum.filter(cells, fn [x, y, count | _] ->
        count >= 2 or
          Enum.any?(
            for(dx <- -1..1, dy <- -1..1, dx != 0 or dy != 0, do: {x + dx, y + dy}),
            &MapSet.member?(keys, &1)
          )
      end)

    if supported == [] do
      cells
    else
      lng_gap = max(1, (max_at(cells, 6) - min_at(cells, 5)) * 0.2)
      lat_gap = max(1, (max_at(cells, 4) - min_at(cells, 3)) * 0.2)

      Enum.filter(cells, fn [_x, _y, _count, minlat, maxlat, minlng, maxlng] ->
        minlng <= max_at(supported, 6) + lng_gap and maxlng >= min_at(supported, 5) - lng_gap and
          minlat <= max_at(supported, 4) + lat_gap and maxlat >= min_at(supported, 3) - lat_gap
      end)
    end
  end

  defp min_at(cells, n), do: cells |> Enum.map(&Enum.at(&1, n)) |> Enum.min()
  defp max_at(cells, n), do: cells |> Enum.map(&Enum.at(&1, n)) |> Enum.max()

  def context(user, params) do
    if Http.present?(params["uuid"]) do
      case Repo.query!(
             "SELECT s.user_id,s.year,s.month,s.h3_hex_ids,s.sharing_settings,u.settings,u.plan,u.active_until FROM stats s JOIN users u ON u.id=s.user_id AND u.deleted_at IS NULL WHERE s.sharing_uuid::text=$1",
             [params["uuid"]]
           ).rows do
        [[id, year, month, cells, sharing, settings, plan, active]] ->
          settings = Dawarich.UserSettings.safe(settings)

          if accessible?(sharing) do
            owner = %{
              id: id,
              timezone: settings["timezone"] || System.get_env("TIME_ZONE", "UTC"),
              plan: plan,
              active_until: active
            }

            first = Date.new!(year, month, 1)

            {:ok,
             %{
               user: owner,
               stat: %{cells: cells},
               shared: true,
               from: Date.to_iso8601(first),
               to: Date.to_iso8601(Date.end_of_month(first)) <> "T23:59:59Z"
             }}
          else
            missing()
          end

        _ ->
          missing()
      end
    else
      stat =
        case month(params["start_date"]) do
          {:ok, year, month} ->
            case Repo.query!(
                   "SELECT h3_hex_ids FROM stats WHERE user_id=$1 AND year=$2 AND month=$3",
                   [user.id, year, month]
                 ).rows do
              [[cells]] -> %{cells: cells}
              [] -> nil
            end

          _ ->
            nil
        end

      {:ok,
       %{
         user: user,
         stat: stat,
         shared: false,
         from: params["start_date"],
         to: params["end_date"]
       }}
    end
  end

  defp month(value) when is_binary(value) do
    case Date.from_iso8601(String.slice(value, 0, 10)) do
      {:ok, d} -> {:ok, d.year, d.month}
      _ -> :error
    end
  end

  defp month(_), do: :error
  defp missing, do: {:error, 404, "Shared stats not found or no longer available"}

  defp accessible?(%{"enabled" => true} = settings) do
    if settings["expiration"] in [nil, false, ""] do
      true
    else
      with {:ok, n} <- Http.strict_timestamp(settings["expires_at"]),
           do: n >= System.system_time(:second)
    end == true
  end

  defp accessible?(_), do: false

  defp empty,
    do: %{
      "type" => "FeatureCollection",
      "features" => [],
      "metadata" => %{"hexagon_count" => 0, "total_points" => 0, "source" => "pre_calculated"}
    }

  defp time(nil), do: nil

  defp time(n) do
    [[text]] =
      Repo.query!("SELECT " <> RailsTime.sql("to_timestamp($1) AT TIME ZONE 'UTC'", 0), [n]).rows

    text
  end
end

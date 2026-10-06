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

      [[count, minlat, maxlat, minlng, maxlng]] =
        Repo.query!(
          "SELECT COUNT(*),ST_YMin(ST_Extent(p.lonlat::geometry)),ST_YMax(ST_Extent(p.lonlat::geometry)),ST_XMin(ST_Extent(p.lonlat::geometry)),ST_XMax(ST_Extent(p.lonlat::geometry)) FROM points p WHERE #{where} AND (p.anomaly=false OR p.anomaly IS NULL)",
          args
        ).rows

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

  def context(user, params) do
    if Http.present?(params["uuid"]) do
      case Repo.query!(
             "SELECT s.user_id,s.year,s.month,s.h3_hex_ids,s.sharing_settings,u.settings,u.plan,u.active_until FROM stats s JOIN users u ON u.id=s.user_id WHERE s.sharing_uuid::text=$1",
             [params["uuid"]]
           ).rows do
        [[id, year, month, cells, sharing, settings, plan, active]] ->
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
               to: Date.to_iso8601(Date.end_of_month(first)) <> "T23:59:59"
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

defmodule Dawarich.MapApi.Hexagons.Boundary do
  @moduledoc false
  import Bitwise
  alias Dawarich.H3.Tables
  @units {{0, 0, 0}, {0, 0, 1}, {0, 1, 0}, {0, 1, 1}, {1, 0, 0}, {1, 0, 1}, {1, 1, 0}}
  @ii [{2, 1, 0}, {1, 2, 0}, {0, 2, 1}, {0, 1, 2}, {1, 0, 2}, {2, 0, 1}]
  @iii [{5, 4, 0}, {1, 5, 0}, {0, 5, 4}, {0, 1, 5}, {4, 0, 5}, {5, 0, 1}]

  def polygon(hex) do
    h = if is_binary(hex), do: String.to_integer(hex, 16), else: hex
    base = h >>> 45 &&& 127
    res = h >>> 52 &&& 15

    if Tables.pentagon?(base),
      do: raise(ArgumentError, "Pentagon boundary requires face projection")

    ring =
      Enum.find_value(0..19, fn face ->
        Enum.find_value(for(i <- 0..2, j <- 0..2, k <- 0..2, do: {i, j, k}), fn coord ->
          if Tables.base_cell(face, coord) == {base, 0}, do: ring(h, res, face, coord)
        end)
      end) || raise(ArgumentError, "Boundary crosses an icosahedron face")

    %{"type" => "Polygon", "coordinates" => [ring ++ [hd(ring)]]}
  end

  defp ring(h, res, face, coord) do
    coord =
      Enum.reduce(1..res//1, coord, fn r, coord ->
        digit = h >>> ((15 - r) * 3) &&& 7
        add(down(coord, if(rem(r, 2) == 1, do: :ap7, else: :ap7r)), elem(@units, digit))
      end)

    coord = coord |> down(:ap3) |> down(:ap3r)

    {coord, adj, verts} =
      if rem(res, 2) == 1, do: {down(coord, :ap7r), res + 1, @iii}, else: {coord, res, @ii}

    verts = Enum.map(verts, &add(coord, &1))
    maxdim = 6 * Integer.pow(7, div(adj, 2))

    if Enum.all?(verts, fn {i, j, k} -> i + j + k <= maxdim end),
      do: Enum.map(verts, &geo(&1, face, adj))
  end

  defp down({i, j, k}, :ap7), do: norm({3 * i + j, 3 * j + k, i + 3 * k})
  defp down({i, j, k}, :ap7r), do: norm({3 * i + k, i + 3 * j, j + 3 * k})
  defp down({i, j, k}, :ap3), do: norm({2 * i + j, 2 * j + k, i + 2 * k})
  defp down({i, j, k}, :ap3r), do: norm({2 * i + k, i + 2 * j, j + 2 * k})

  defp norm({i, j, k}),
    do:
      (
        n = min(i, min(j, k))
        {i - n, j - n, k - n}
      )

  defp add({i, j, k}, {a, b, c}), do: norm({i + a, j + b, k + c})

  defp geo({i, j, k}, face, res) do
    x = i - k - 0.5 * (j - k)
    y = (j - k) * 0.86602540378443864676

    r =
      :math.atan(
        :math.sqrt(x * x + y * y) / :math.pow(:math.sqrt(7), res) / 3 * 0.381966011250105
      )

    az = Tables.face_axis(face) - :math.atan2(y, x)
    {lat, lng} = Tables.face_center(face)
    slat = :math.sin(lat) * :math.cos(r) + :math.cos(lat) * :math.sin(r) * :math.cos(az)
    plat = :math.asin(max(-1.0, min(1.0, slat)))

    plng =
      lng +
        :math.atan2(
          :math.sin(az) * :math.sin(r) * :math.cos(lat),
          :math.cos(r) - :math.sin(lat) * slat
        )

    plng =
      if plng > :math.pi(),
        do: plng - 2 * :math.pi(),
        else: if(plng < -:math.pi(), do: plng + 2 * :math.pi(), else: plng)

    [plng * 180 / :math.pi(), plat * 180 / :math.pi()]
  end
end

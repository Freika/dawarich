defmodule Dawarich.Transportation.FeatureExtractor do
  @moduledoc false

  @sql """
  SELECT p.id AS point_id, p.timestamp AS ts, p.accuracy, p.velocity, p.motion_data,
         ST_X(p.lonlat::geometry) AS lon, ST_Y(p.lonlat::geometry) AS lat,
         p.timestamp - LAG(p.timestamp) OVER w AS dt,
         ST_Distance(p.lonlat, LAG(p.lonlat) OVER w) AS dist_m,
         degrees(ST_Azimuth((LAG(p.lonlat) OVER w)::geometry, p.lonlat::geometry)) AS bearing_deg
  FROM points p
  WHERE p.track_id = $1 AND p.anomaly IS NOT TRUE
  WINDOW w AS (ORDER BY p.timestamp, p.id)
  ORDER BY p.timestamp, p.id
  """

  @float_regex ~r/^[+-]?(?:\d+(?:_\d+)*)(?:\.\d+(?:_\d+)*)?(?:[eE][+-]?\d+(?:_\d+)*)?$/

  def rows(repo, track_id) do
    repo.query!(@sql, [track_id], log: false).rows
    |> Enum.map(&row_to_map/1)
  end

  defp row_to_map([
         point_id,
         ts,
         accuracy,
         velocity,
         motion_data,
         lon,
         lat,
         dt,
         dist_m,
         bearing_deg
       ]) do
    %{
      point_id: point_id,
      ts: ts,
      accuracy: to_float(accuracy),
      velocity: parse_velocity(velocity),
      motion_data: parse_motion_data(motion_data),
      lon: to_float(lon),
      lat: to_float(lat),
      dt: dt,
      dist_m: to_float(dist_m),
      bearing_deg: to_float(bearing_deg)
    }
  end

  defp to_float(nil), do: nil
  defp to_float(v) when is_float(v), do: v
  defp to_float(v) when is_integer(v), do: v * 1.0

  def parse_velocity(nil), do: nil
  def parse_velocity(""), do: nil

  def parse_velocity(raw) when is_binary(raw) do
    trimmed = String.trim(raw)

    if Regex.match?(@float_regex, trimmed) do
      trimmed
      |> String.replace("_", "")
      |> normalize_float_literal()
      |> Float.parse()
      |> case do
        {value, ""} -> value
        _ -> nil
      end
    else
      nil
    end
  end

  defp normalize_float_literal(s) do
    if String.contains?(s, ".") do
      s
    else
      case String.split(s, ~r/[eE]/, parts: 2) do
        [mantissa, exponent] -> mantissa <> ".0e" <> exponent
        [mantissa] -> mantissa <> ".0"
      end
    end
  end

  def parse_motion_data(nil), do: %{}
  def parse_motion_data(""), do: %{}

  def parse_motion_data(raw) when is_binary(raw) do
    case Jason.decode(raw) do
      {:ok, value} -> value
      {:error, _} -> %{}
    end
  end

  def parse_motion_data(raw) when is_map(raw), do: raw
  def parse_motion_data(_raw), do: %{}
end

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

  @digits "\\d(?:_?\\d)*"
  @decimal_regex ~r/^[+-]?(?:#{@digits}(?:\.(?:#{@digits})?)?|\.#{@digits})(?:[eE][+-]?#{@digits})?$/
  @hex_regex ~r/^[+-]?0[xX][0-9a-fA-F](?:_?[0-9a-fA-F])*$/

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

    cond do
      Regex.match?(@hex_regex, trimmed) -> parse_hex(trimmed)
      Regex.match?(@decimal_regex, trimmed) -> parse_decimal(trimmed)
      true -> nil
    end
  end

  defp parse_hex(str) do
    {sign, digits} =
      case str do
        "+" <> rest -> {1, rest}
        "-" <> rest -> {-1, rest}
        rest -> {1, rest}
      end

    hex_digits = digits |> String.slice(2..-1//1) |> String.replace("_", "")

    case Integer.parse(hex_digits, 16) do
      {value, ""} -> sign * value * 1.0
      _ -> nil
    end
  end

  defp parse_decimal(str) do
    {sign, rest} =
      case str do
        "+" <> tail -> {"", tail}
        "-" <> tail -> {"-", tail}
        tail -> {"", tail}
      end

    rest = String.replace(rest, "_", "")

    {mantissa, exponent} =
      case String.split(rest, ~r/[eE]/, parts: 2) do
        [m, e] -> {m, e}
        [m] -> {m, nil}
      end

    mantissa = normalize_mantissa(mantissa)
    normalized = sign <> mantissa <> if(exponent, do: "e" <> exponent, else: "")

    case Float.parse(normalized) do
      {value, ""} -> value
      _ -> nil
    end
  end

  defp normalize_mantissa(mantissa) do
    cond do
      String.starts_with?(mantissa, ".") -> "0" <> mantissa
      String.ends_with?(mantissa, ".") -> mantissa <> "0"
      not String.contains?(mantissa, ".") -> mantissa <> ".0"
      true -> mantissa
    end
  end

  def parse_motion_data(nil), do: %{}
  def parse_motion_data(""), do: %{}
  def parse_motion_data(raw), do: raw
end

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
  @xdigits "[0-9a-fA-F](?:_?[0-9a-fA-F])*"
  @decimal_regex ~r/\A[+-]?(?:#{@digits}(?:\.(?:#{@digits})?)?|\.#{@digits})(?:[eE][+-]?#{@digits})?\z/
  @hex_regex ~r/\A(?<sign>[+-]?)0[xX](?<int>#{@xdigits})?(?:(?<dot>\.)(?<frac>#{@xdigits})?)?(?:[pP](?<exp>[+-]?#{@digits}))?\z/
  @zero_run_regex ~r/\A[+-]?0[xX]0++(?![0-9a-fA-F.])/
  @bare_zero_run_regex ~r/\A[+-]?0[xX]0+(?:[pP][+-]?\d+)?\z/
  @leading_space ~r/\A[ \t\n\x0B\f\r]+/
  @trailing_space ~r/[ \t\n\x0B\f\r]+\z/

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
    unpadded = Regex.replace(@leading_space, raw, "")
    trimmed = Regex.replace(@trailing_space, unpadded, "")

    cond do
      Regex.match?(@zero_run_regex, unpadded) and
          not Regex.match?(@bare_zero_run_regex, unpadded) ->
        nil

      captures = Regex.named_captures(@hex_regex, trimmed) ->
        parse_hex(captures)

      Regex.match?(@decimal_regex, trimmed) ->
        parse_decimal(trimmed)

      true ->
        nil
    end
  end

  defp parse_hex(%{"int" => "", "dot" => ""}), do: nil

  defp parse_hex(%{"sign" => sign, "int" => int, "frac" => frac, "exp" => exponent}) do
    value = int |> strip() |> String.trim_leading("0") |> hex_value(strip(frac), exponent)
    if value && sign == "-", do: -value, else: value
  end

  defp hex_value(int, frac, exponent) do
    {adj, aadj, nd0} =
      int |> hex_digits() |> Enum.reduce({0.0, 1.0, -4}, &accumulate_int/2)

    {frac, nd0} =
      if int == "" do
        zeros = byte_size(frac) - byte_size(String.trim_leading(frac, "0"))
        {String.trim_leading(frac, "0"), nd0 - 4 * zeros}
      else
        {frac, nd0}
      end

    {adj, _aadj} = frac |> hex_digits() |> Enum.reduce_while({adj, aadj}, &accumulate_frac/2)
    exponent = if exponent == "", do: 0, else: String.to_integer(strip(exponent))

    ldexp(adj, nd0 + exponent)
  end

  defp strip(digits), do: String.replace(digits, "_", "")

  defp hex_digits(digits), do: for(<<d::binary-1 <- digits>>, do: String.to_integer(d, 16))

  defp accumulate_int(d, {adj, aadj, nd0}), do: {adj + aadj * d, aadj / 16, nd0 + 4}

  defp accumulate_frac(d, {adj, aadj}) do
    adj = adj + aadj * d
    aadj = aadj / 16
    if aadj == 0.0, do: {:halt, {adj, aadj}}, else: {:cont, {adj, aadj}}
  end

  defp ldexp(adj, _n) when adj == 0.0, do: 0.0

  defp ldexp(adj, n) do
    <<0::1, e::11, f::52>> = <<adj::float>>
    {m, k} = if e == 0, do: {f, n - 1074}, else: {f + 0x10000000000000, n + e - 1075}
    scale(m, k)
  end

  defp scale(m, k) when k >= -1074 do
    if length(Integer.digits(m, 2)) + k > 1024, do: nil, else: m * :math.pow(2, k)
  end

  defp scale(_m, k) when k < -1074 - 54, do: 0.0

  defp scale(m, k) do
    divisor = Bitwise.bsl(1, -1074 - k)
    {q, r} = {div(m, divisor), rem(m, divisor)}

    n =
      cond do
        2 * r > divisor -> q + 1
        2 * r == divisor and rem(q, 2) == 1 -> q + 1
        true -> q
      end

    n * :math.pow(2, -1074)
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

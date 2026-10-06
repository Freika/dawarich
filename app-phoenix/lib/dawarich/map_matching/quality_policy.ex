defmodule Dawarich.MapMatching.QualityPolicy do
  def version, do: 1

  def call(opts) do
    geometry = Keyword.fetch!(opts, :geometry)
    stats = Keyword.fetch!(opts, :stats)
    count = Keyword.fetch!(opts, :input_point_count)

    reasons =
      [
        {valid_geometry?(geometry), "invalid_geometry"},
        {integer(value(stats, :matched)) + integer(value(stats, :interpolated)) > 0,
         "no_matched_points"},
        {integer(count) >= 2, "invalid_input_point_count"}
      ]
      |> Enum.reject(&elem(&1, 0))
      |> Enum.map(&elem(&1, 1))

    %{accepted: reasons == [], reasons: reasons}
  end

  defp valid_geometry?(geometry) when is_map(geometry) do
    lines =
      case value(geometry, :type) do
        "LineString" -> [value(geometry, :coordinates)]
        "MultiLineString" -> value(geometry, :coordinates)
        _ -> nil
      end

    is_list(lines) and lines != [] and Enum.all?(lines, &valid_line?/1)
  end

  defp valid_geometry?(_), do: false

  defp valid_line?(line) when is_list(line) and length(line) >= 2 do
    Enum.all?(line, fn
      [lon, lat | _] when is_number(lon) and is_number(lat) -> true
      _ -> false
    end)
  end

  defp valid_line?(_), do: false
  defp value(map, key), do: Map.get(map, Atom.to_string(key), Map.get(map, key))
  defp integer(value) when is_number(value), do: trunc(value)

  defp integer(value) when is_binary(value) do
    case Integer.parse(String.trim_leading(value)) do
      {number, _} -> number
      :error -> 0
    end
  end

  defp integer(_), do: 0
end

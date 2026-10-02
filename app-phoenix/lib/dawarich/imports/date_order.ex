defmodule Dawarich.Imports.DateOrder do
  @moduledoc false

  def fields(y, m, d, bc \\ false) do
    {y, m, d} = if y && m && !d, do: {nil, y, m}, else: {y, m, d}

    {y, d} =
      if !y && d && (byte_size(d) > 2 || String.starts_with?(d, "'")), do: {d, nil}, else: {y, d}

    {y, d} = trailing_year(y, d)

    {y, m, d} =
      if m && (byte_size(m) > 2 || String.starts_with?(m, "'")), do: {m, d, y}, else: {y, m, d}

    {y, d} = if d && (byte_size(d) > 2 || String.starts_with?(d, "'")), do: {d, y}, else: {y, d}

    result =
      put(%{}, "year", y, ~r/[+-]?\d+/) |> put("mon", m, ~r/\d+/) |> put("mday", d, ~r/\d+/)

    if bc, do: Map.put(result, "_bc", true), else: result
  end

  defp trailing_year(nil, d), do: {nil, d}

  defp trailing_year(y, d) do
    case Regex.run(~r/[+-]?\d+/, y, return: :index) do
      [{start, length}] when start + length < byte_size(y) -> {d, binary_part(y, start, length)}
      _ -> {y, d}
    end
  end

  defp put(map, _key, nil, _pattern), do: map

  defp put(map, key, string, pattern) do
    case Regex.run(pattern, string) do
      [number] -> Map.put(map, key, String.to_integer(number))
      _ -> map
    end
  end
end

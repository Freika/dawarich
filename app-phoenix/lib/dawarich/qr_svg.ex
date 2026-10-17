defmodule Dawarich.QrSvg do
  @moduledoc false

  @deltas %{up: {0, -1}, down: {0, 1}, left: {-1, 0}, right: {1, 0}}
  @commands %{up: "v-", down: "v", left: "h-", right: "h"}

  def api_key(root_url, api_key, size \\ 6),
    do: svg(~s|{"server_url":#{json(root_url)},"api_key":#{json(api_key)}}|, size)

  def svg(data, size \\ 6) do
    {count, path} =
      Dawarich.QrCache.fetch(data, fn ->
        rows = Dawarich.QrCode.modules(data)
        {length(rows), path(rows)}
      end)

    serialize(count, path, size)
  end

  def otp(data, size \\ 6) do
    rows = Dawarich.QrCode.modules(data)
    serialize(length(rows), path(rows), size)
  end

  defp serialize(count, path, size) do
    width = count * size + 10

    ~s|<?xml version="1.0" standalone="yes"?><svg version="1.1" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" xmlns:ev="http://www.w3.org/2001/xml-events" width="100%" height="100%" viewBox="0 0 #{width} #{width}" preserveAspectRatio="xMidYMid meet" shape-rendering="crispEdges"><rect width="#{width}" height="#{width}" x="0" y="0" fill="#fff"/><path d="#{path}" fill="#000" transform="translate(5,5) scale(#{size})"/></svg>|
  end

  defp json(value) do
    value
    |> Jason.encode!()
    |> String.replace(["<", ">", "&"], &("\\u00" <> Base.encode16(&1, case: :lower)))
  end

  def path(rows) do
    n = length(rows)
    grid = rows |> Enum.map(&List.to_tuple/1) |> List.to_tuple()
    dark? = fn r, c -> r in 0..(n - 1) and c in 0..(n - 1) and elem(elem(grid, r), c) end

    horizontal =
      for row <- 0..n,
          col <- 0..(n - 1),
          edge = horizontal(dark?.(row - 1, col), dark?.(row, col), row, col),
          do: edge

    vertical =
      for row <- 0..(n - 1),
          col <- 0..n,
          edge = vertical(dark?.(row, col - 1), dark?.(row, col), row, col),
          do: edge

    edges =
      Enum.reduce(horizontal ++ vertical, %{}, fn {x, y, _} = e, acc ->
        Map.update(acc, {y, x}, [e], &(&1 ++ [e]))
      end)

    trace(edges, {0, 0}, n + 1, [])
  end

  defp horizontal(true, false, row, col), do: {col + 1, row, :left}
  defp horizontal(false, true, row, col), do: {col, row, :right}
  defp horizontal(_above, _below, _row, _col), do: nil

  defp vertical(true, false, row, col), do: {col, row, :down}
  defp vertical(false, true, row, col), do: {col, row + 1, :up}
  defp vertical(_left, _right, _row, _col), do: nil

  defp trace(edges, _from, _size, parts) when map_size(edges) == 0,
    do: parts |> Enum.reverse() |> Enum.join()

  defp trace(edges, from, size, parts) do
    {y, x} = start = first_cell(edges, from, size)
    [{sx, sy, _} = edge | _] = Map.fetch!(edges, start)
    {edges, body} = walk(edges, edge, nil, 0, [])
    trace(edges, {y, x}, size, ["M#{sx} #{sy}#{body}z" | parts])
  end

  defp first_cell(edges, {y, x}, size) do
    Enum.find_value(y..(size - 1), fn row ->
      Enum.find_value(if(row == y, do: x, else: 0)..(size - 1)//1, fn col ->
        if Map.has_key?(edges, {row, col}), do: {row, col}
      end)
    end)
  end

  defp walk(edges, nil, _dir, _count, out), do: {edges, out |> Enum.reverse() |> Enum.join()}

  defp walk(edges, {x, y, dir} = edge, current, count, out) do
    edges =
      case Map.fetch!(edges, {y, x}) -- [edge] do
        [] -> Map.delete(edges, {y, x})
        rest -> Map.put(edges, {y, x}, rest)
      end

    {out, count} =
      cond do
        dir == current -> {out, count + 1}
        current == nil -> {out, 1}
        true -> {["#{@commands[current]}#{count}" | out], 1}
      end

    {dx, dy} = @deltas[dir]

    next =
      case Map.get(edges, {y + dy, x + dx}) do
        [first | _] -> first
        nil -> nil
      end

    walk(edges, next, dir, count, out)
  end
end

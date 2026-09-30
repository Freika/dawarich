defmodule Dawarich.QrMatrix do
  @moduledoc false

  import Bitwise

  @tables Path.expand("../../priv/qr_tables.json", __DIR__)
  @external_resource @tables
  @positions @tables |> File.read!() |> Jason.decode!() |> Map.fetch!("positions")
  @format_h 2
  @g15 1335
  @g18 7973
  @g15_mask 21522

  def build(version, codes) do
    size = version * 4 + 17
    data = :binary.list_to_bin(codes)
    base = base(version, size)

    mask =
      Enum.min_by(0..7, fn mask ->
        base |> place(version, size, data, mask, true) |> rows(size) |> lost_points()
      end)

    base |> place(version, size, data, mask, false) |> rows(size)
  end

  defp base(version, size) do
    probes =
      for {row, col} <- [{0, 0}, {size - 7, 0}, {0, size - 7}],
          r <- -1..7,
          c <- -1..7,
          (row + r) in 0..(size - 1),
          (col + c) in 0..(size - 1),
          into: %{} do
        {{row + r, col + c},
         (r in 0..6 and c in [0, 6]) or (c in 0..6 and r in [0, 6]) or (r in 2..4 and c in 2..4)}
      end

    positions = Enum.at(@positions, version - 1)

    adjusted =
      for row <- positions,
          col <- positions,
          reduce: probes do
        acc -> if Map.has_key?(acc, {row, col}), do: acc, else: adjust(acc, row, col)
      end

    for i <- 8..(size - 9)//1, cell <- [{i, 6}, {6, i}], into: adjusted do
      {cell, rem(i, 2) == 0}
    end
  end

  defp adjust(matrix, row, col) do
    for r <- -2..2, c <- -2..2, into: matrix do
      {{row + r, col + c}, abs(r) == 2 or abs(c) == 2 or (r == 0 and c == 0)}
    end
  end

  defp place(base, version, size, data, mask, test) do
    format = bxor(bch(bor(bsl(@format_h, 3), mask), 10, @g15), @g15_mask)

    matrix =
      for i <- 0..14, cell <- format_cells(i, size), into: base do
        {cell, not test and band(bsr(format, i), 1) == 1}
      end

    matrix = Map.put(matrix, {size - 8, 8}, not test)

    matrix =
      if version >= 7 do
        info = bch(version, 12, @g18)

        for i <- 0..17,
            cell <- [{div(i, 3), rem(i, 3) + size - 11}, {rem(i, 3) + size - 11, div(i, 3)}],
            into: matrix do
          {cell, not test and band(bsr(info, i), 1) == 1}
        end
      else
        matrix
      end

    fill(matrix, size, data, mask)
  end

  defp format_cells(i, size) do
    row = if i < 6, do: i, else: if(i < 8, do: i + 1, else: size - 15 + i)
    col = if i < 8, do: size - i - 1, else: if(i < 9, do: 15 - i, else: 14 - i)
    [{row, 8}, {8, col}]
  end

  defp bch(data, shift, g), do: bor(bsl(data, shift), reduce_bch(bsl(data, shift), g))

  defp reduce_bch(d, g) do
    if digits(d) >= digits(g), do: reduce_bch(bxor(d, bsl(g, digits(d) - digits(g))), g), else: d
  end

  defp digits(0), do: 0
  defp digits(n), do: 1 + digits(bsr(n, 1))

  defp fill(matrix, size, data, mask) do
    {matrix, _index} =
      (size - 1)..1//-2
      |> Enum.map(&if(&1 <= 6, do: &1 - 1, else: &1))
      |> Enum.with_index()
      |> Enum.reduce({matrix, 0}, fn {col, n}, acc ->
        rows = if rem(n, 2) == 0, do: (size - 1)..0//-1, else: 0..(size - 1)

        for row <- rows, c <- [col, col - 1], reduce: acc do
          {m, i} ->
            if Map.has_key?(m, {row, c}),
              do: {m, i},
              else: {Map.put(m, {row, c}, bit(data, i) != mask?(mask, row, c)), i + 1}
        end
      end)

    matrix
  end

  defp bit(data, i) when i < bit_size(data) do
    <<_::size(i), b::1, _::bitstring>> = data
    b == 1
  end

  defp bit(_data, _i), do: false

  defp mask?(0, i, j), do: rem(i + j, 2) == 0
  defp mask?(1, i, _j), do: rem(i, 2) == 0
  defp mask?(2, _i, j), do: rem(j, 3) == 0
  defp mask?(3, i, j), do: rem(i + j, 3) == 0
  defp mask?(4, i, j), do: rem(div(i, 2) + div(j, 3), 2) == 0
  defp mask?(5, i, j), do: rem(i * j, 2) + rem(i * j, 3) == 0
  defp mask?(6, i, j), do: rem(rem(i * j, 2) + rem(i * j, 3), 2) == 0
  defp mask?(7, i, j), do: rem(rem(i * j, 3) + rem(i + j, 2), 2) == 0

  defp rows(matrix, size),
    do: for(r <- 0..(size - 1), do: for(c <- 0..(size - 1), do: Map.fetch!(matrix, {r, c})))

  def lost_points(rows) do
    n = length(rows)
    edge_row = List.duplicate(:edge, n)

    same =
      [edge_row | rows]
      |> Kernel.++([edge_row])
      |> Enum.chunk_every(3, 1, :discard)
      |> Enum.map(&same_row_points/1)
      |> Enum.sum()

    blocks =
      rows
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(&block_row_points/1)
      |> Enum.sum()

    columns = for c <- 0..(n - 1), do: for(row <- rows, do: Enum.at(row, c))
    patterns = (rows ++ columns) |> Enum.map(&finder_runs/1) |> Enum.sum()
    dark = rows |> List.flatten() |> Enum.count(& &1)

    same + blocks + patterns * 40 + abs(100 * (dark / (n * n)) - 50) / 5 * 10
  end

  defp same_row_points([above, current, below]) do
    [above, current, below]
    |> Enum.map(&([:edge] ++ &1 ++ [:edge]))
    |> Enum.zip()
    |> Enum.map(&Tuple.to_list/1)
    |> Enum.chunk_every(3, 1, :discard)
    |> Enum.reduce(0, fn [left, [_, cell, _] = mid, right], acc ->
      neighbors = left ++ [hd(mid), List.last(mid)] ++ right
      count = Enum.count(neighbors, &(&1 == cell))
      if count > 5, do: acc + count - 2, else: acc
    end)
  end

  defp block_row_points([top, bottom]) do
    top
    |> Enum.zip(bottom)
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.count(fn [{t0, b0}, {t1, b1}] -> t0 == b0 and t0 == t1 and t0 == b1 end)
    |> Kernel.*(3)
  end

  defp finder_runs([true, false, true, true, true, false, true | _] = line),
    do: 1 + finder_runs(tl(line))

  defp finder_runs([_ | rest]) when length(rest) >= 6, do: finder_runs(rest)
  defp finder_runs(_line), do: 0
end

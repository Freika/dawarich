defmodule Dawarich.H3.Coordinates do
  @moduledoc false
  def norm({i, j, k}) do
    n = min(i, min(j, k))
    {i - n, j - n, k - n}
  end

  def add({i, j, k}, {a, b, c}), do: norm({i + a, j + b, k + c})
  def sub({i, j, k}, {a, b, c}), do: norm({i - a, j - b, k - c})
  def scale({i, j, k}, n), do: {i * n, j * n, k * n}
  def down({i, j, k}, :ap7), do: norm({3 * i + j, 3 * j + k, i + 3 * k})
  def down({i, j, k}, :ap7r), do: norm({3 * i + k, i + 3 * j, j + 3 * k})
  def down({i, j, k}, :ap3), do: norm({2 * i + j, 2 * j + k, i + 2 * k})
  def down({i, j, k}, :ap3r), do: norm({2 * i + k, i + 2 * j, j + 2 * k})

  def up({i, j, k}),
    do: norm({round((2 * (i - k) + j - k) / 7), round((3 * (j - k) - i + k) / 7), 0})

  def rotate({i, j, k}, :ccw), do: norm({i + k, i + j, j + k})
  def rotate({i, j, k}, :cw), do: norm({i + j, j + k, i + k})
  def rotate(coord, 0), do: coord
  def rotate(coord, n), do: rotate(rotate(coord, :ccw), n - 1)
  def xy({i, j, k}), do: {i - k - 0.5 * (j - k), (j - k) * 0.86602540378443864676}
end

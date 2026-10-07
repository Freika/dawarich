defmodule Dawarich.MapApi.Hexagons.Boundary do
  @moduledoc false
  alias Dawarich.H3.{Coordinates, Face, FaceTables}
  @ii [{2, 1, 0}, {1, 2, 0}, {0, 2, 1}, {0, 1, 2}, {1, 0, 2}, {2, 0, 1}]
  @iii [{5, 4, 0}, {1, 5, 0}, {0, 5, 4}, {0, 1, 5}, {4, 0, 5}, {5, 0, 1}]

  def polygon(hex) do
    h = if is_binary(hex), do: String.to_integer(hex, 16), else: hex
    {{face, coord}, res, pentagon} = Face.decode(h)
    coord = coord |> Coordinates.down(:ap3) |> Coordinates.down(:ap3r)
    odd = rem(res, 2) == 1
    coord = if odd, do: Coordinates.down(coord, :ap7r), else: coord
    adj = res + rem(res, 2)
    vertices = if odd, do: @iii, else: @ii
    vertices = if pentagon, do: Enum.take(vertices, 5), else: vertices
    vertices = Enum.map(vertices, &{face, Coordinates.add(coord, &1)})
    n = length(vertices)

    {ring, _last} =
      Enum.reduce(0..n, {[], nil}, fn v, {ring, last} ->
        original = Enum.at(vertices, rem(v, n))
        {overage, current} = Face.adjust(original, adj, false, true)
        current = if pentagon, do: Face.settle(current, adj, true), else: current

        extra =
          if odd and last do
            crossing(original, current, last, vertices, v, face, adj, pentagon)
          else
            []
          end

        {f, c} = current
        point = if v < n, do: [Face.geo(Coordinates.xy(c), f, adj)], else: []
        {ring ++ extra ++ point, {current, overage}}
      end)

    %{"type" => "Polygon", "coordinates" => [ring ++ [hd(ring)]]}
  end

  defp crossing(
         _original,
         {face, coord},
         {{previous, prev_coord}, _},
         _vertices,
         _v,
         _home,
         res,
         true
       ) do
    {previous, translated} =
      Face.transform({face, coord}, FaceTables.direction(face, previous), res, true)

    a = Coordinates.xy(prev_coord)
    b = Coordinates.xy(translated)
    inter = intersection(a, b, edge(FaceTables.direction(previous, face), res))
    [Face.geo(inter, previous, res)]
  end

  defp crossing(
         {_face, coord},
         {face, _},
         {{previous, _}, overage},
         vertices,
         v,
         home,
         res,
         false
       ) do
    if face != previous and overage != :edge do
      {_, last_coord} = Enum.at(vertices, rem(v + 5, 6))
      a = Coordinates.xy(last_coord)
      b = Coordinates.xy(coord)
      next = if previous == home, do: face, else: previous
      inter = intersection(a, b, edge(FaceTables.direction(home, next), res))
      if same?(a, inter) or same?(b, inter), do: [], else: [Face.geo(inter, home, res)]
    else
      []
    end
  end

  defp edge(direction, res) do
    m = 2 * Integer.pow(7, div(res, 2))
    v0 = {3.0 * m, 0.0}
    v1 = {-1.5 * m, 3 * 0.86602540378443864676 * m}
    v2 = {-1.5 * m, -3 * 0.86602540378443864676 * m}

    case direction do
      1 -> {v0, v1}
      3 -> {v1, v2}
      2 -> {v2, v0}
    end
  end

  defp intersection({ax, ay}, {bx, by}, {{cx, cy}, {dx, dy}}) do
    denominator = (bx - ax) * (dy - cy) - (by - ay) * (dx - cx)
    t = ((cx - ax) * (dy - cy) - (cy - ay) * (dx - cx)) / denominator
    <<t::float-32>> = <<t::float-32>>
    {ax + t * (bx - ax), ay + t * (by - ay)}
  end

  defp same?({ax, ay}, {bx, by}), do: ax == bx and ay == by
end

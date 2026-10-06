defmodule Dawarich.MapApi.Fog do
  @moduledoc false
  alias Dawarich.{RailsTime, Repo, RubyInteger}
  alias Dawarich.Tiles.Http

  def fetch(user, params) do
    required = Enum.find(~w(start_date end_date), &(not Http.present?(params[&1])))

    if required do
      {:error, 400, "Missing required parameter: #{required}"}
    else
      RailsTime.with_zone(user.timezone, fn ->
        with {:ok, from} <- Http.strict_timestamp(params["start_date"]),
             {:ok, to} <- Http.strict_timestamp(params["end_date"]) do
          collect(user, from, to)
        else
          _ -> {:error, 400, "Invalid date format"}
        end
      end)
    end
  rescue
    _ -> {:error, 500, "Failed to generate hexagon grid"}
  end

  defp collect(user, from, to) do
    [[first, last]] =
      Repo.query!(
        "SELECT extract(year FROM a)::int*100+extract(month FROM a)::int,extract(year FROM b)::int*100+extract(month FROM b)::int FROM (SELECT to_timestamp($1) AS a,to_timestamp($2) AS b)x",
        [from, to]
      ).rows

    cutoff = Http.window(user)

    plan =
      if cutoff,
        do:
          "AND year*100+month >= (extract(year FROM to_timestamp(#{cutoff}))::int*100+extract(month FROM to_timestamp(#{cutoff}))::int)",
        else: ""

    rows =
      Repo.query!(
        "SELECT h3_hex_ids FROM stats WHERE user_id=$1 AND year*100+month BETWEEN $2 AND $3 #{plan} ORDER BY id",
        [user.id, first, last]
      ).rows

    ids =
      Enum.flat_map(rows, fn
        [cells] when is_list(cells) ->
          Enum.flat_map(cells, fn
            [index, _count, earliest, latest] ->
              if present?(index) and overlaps?(earliest, latest, from, to), do: [index], else: []

            [index | _] ->
              if present?(index), do: [index], else: []

            _ ->
              []
          end)

        _ ->
          []
      end)
      |> Enum.uniq()

    {:ok, %{"h3_indexes" => ids, "metadata" => %{"count" => length(ids)}}}
  end

  defp present?(v), do: v not in [nil, false, ""] and v != [] and v != %{}

  defp overlaps?(earliest, latest, from, to),
    do:
      not present?(earliest) or not present?(latest) or
        (RubyInteger.to_i(earliest) <= to and RubyInteger.to_i(latest) >= from)
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

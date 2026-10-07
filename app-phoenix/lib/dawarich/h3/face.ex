defmodule Dawarich.H3.Face do
  @moduledoc false
  import Bitwise
  alias Dawarich.H3.{Coordinates, FaceTables, Tables}
  @units {{0, 0, 0}, {0, 0, 1}, {0, 1, 0}, {0, 1, 1}, {1, 0, 0}, {1, 0, 1}, {1, 1, 0}}
  @cw {0, 3, 6, 2, 5, 1, 4}

  def decode(h) do
    res = h >>> 52 &&& 15
    base = h >>> 45 &&& 127

    unless h >>> 59 == 1 and (h >>> 56 &&& 7) == 0 and base < 122 and
             Enum.all?(1..res//1, &(digit(h, &1) < 7)) and
             Enum.all?((res + 1)..15//1, &(digit(h, &1) == 7)),
           do: raise(ArgumentError, "Invalid H3 index")

    pent_base = Tables.pentagon?(base)
    lead = Enum.find_value(1..res//1, 0, fn r -> if digit(h, r) != 0, do: digit(h, r) end)
    if pent_base and lead == 1, do: raise(ArgumentError, "Invalid H3 pentagon sequence")
    {face, start} = FaceTables.home(base)
    rotated = pent_base and lead == 5

    coord =
      Enum.reduce(1..res//1, start, fn r, c ->
        d = digit(h, r)
        d = if rotated, do: elem(@cw, d), else: d

        Coordinates.add(
          Coordinates.down(c, if(rem(r, 2) == 1, do: :ap7, else: :ap7r)),
          elem(@units, d)
        )
      end)

    odd = rem(res, 2) == 1
    adjusted = if odd, do: Coordinates.down(coord, :ap7r), else: coord

    {overage, {next, moved}} =
      adjust(
        {face, adjusted},
        res + rem(res, 2),
        pent_base and if(rotated, do: elem(@cw, lead), else: lead) == 4,
        false
      )

    location =
      if overage == :none do
        {face, coord}
      else
        {next, moved} =
          if pent_base, do: settle({next, moved}, res + rem(res, 2), false), else: {next, moved}

        {next, if(odd, do: Coordinates.up(moved), else: moved)}
      end

    {location, res, pent_base and lead == 0}
  end

  def adjust({face, {i, j, k} = coord} = location, res, leading4, substrate) do
    maxdim = 2 * Integer.pow(7, div(res, 2)) * if(substrate, do: 3, else: 1)

    cond do
      substrate and i + j + k == maxdim ->
        {:edge, location}

      i + j + k > maxdim ->
        direction =
          cond do
            k > 0 and j > 0 -> 3
            k > 0 -> 2
            true -> 1
          end

        coord =
          if direction == 2 and leading4 do
            origin = {maxdim, 0, 0}
            coord |> Coordinates.sub(origin) |> Coordinates.rotate(:cw) |> Coordinates.add(origin)
          else
            coord
          end

        {next, moved} = transform({face, coord}, direction, res, substrate)
        {a, b, c} = moved
        {if(substrate and a + b + c == maxdim, do: :edge, else: :new), {next, moved}}

      true ->
        {:none, location}
    end
  end

  def settle(location, res, substrate) do
    case adjust(location, res, false, substrate) do
      {:new, next} -> settle(next, res, substrate)
      {_, next} -> next
    end
  end

  def transform({face, coord}, direction, res, substrate) do
    {next, translation, rotations} = FaceTables.neighbor(face, direction)
    scale = Integer.pow(7, div(res, 2)) * if(substrate, do: 3, else: 1)

    {next,
     coord
     |> Coordinates.rotate(rotations)
     |> Coordinates.add(Coordinates.scale(translation, scale))}
  end

  def geo({x, y}, face, res) do
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

  defp digit(h, r), do: h >>> ((15 - r) * 3) &&& 7
end

defmodule Dawarich.H3 do
  @moduledoc false

  import Bitwise

  alias Dawarich.H3.Tables

  @pi_180 0.0174532925199432957692369076848861271111
  @two_pi 6.28318530717958647692528676655900576839433
  @epsilon 0.0000000000000001
  @sqrt7 2.6457513110645905905016157536392604257102
  @res0_u_gnomonic 0.38196601125010500003
  @ap7_rot_rads 0.333473172251832115336090755351601070065900389
  @sin60 0.8660254037844386467637231707529361834714
  @one_third 1.0 / 3.0
  @two_thirds 2.0 / 3.0
  @base 1 <<< 59 ||| 0x1FFF_FFFF_FFFF
  @unit %{
    {0, 0, 0} => 0,
    {0, 0, 1} => 1,
    {0, 1, 0} => 2,
    {0, 1, 1} => 3,
    {1, 0, 0} => 4,
    {1, 0, 1} => 5,
    {1, 1, 0} => 6
  }
  @ccw %{1 => 5, 5 => 4, 4 => 6, 6 => 2, 2 => 3, 3 => 1}
  @cw %{1 => 3, 3 => 2, 2 => 6, 6 => 4, 4 => 5, 5 => 1}

  def from_geo({lat, lng}, res) when is_number(lat) and is_number(lng) and res in 0..15 do
    if lat > 90 or lat < -90 or lng > 180 or lng < -180,
      do: raise(ArgumentError, "Invalid coordinates")

    {face, x, y} = hex2d(lat * @pi_180, lng * @pi_180, res)
    encode(face, ijk(x, y), res)
  end

  def hex(index), do: index |> Integer.to_string(16) |> String.downcase()

  defp hex2d(lat, lng, res) do
    r = :math.cos(lat)
    {face, sqd} = nearest_face({:math.cos(lng) * r, :math.sin(lng) * r, :math.sin(lat)})
    r = :math.acos(1 - sqd / 2)

    if r < @epsilon do
      {face, 0.0, 0.0}
    else
      {face_lat, face_lng} = Tables.face_center(face)
      theta = pos_angle(Tables.face_axis(face) - pos_angle(azimuth(face_lat, face_lng, lat, lng)))
      theta = if rem(res, 2) == 1, do: pos_angle(theta - @ap7_rot_rads), else: theta
      r = Enum.reduce(1..res//1, :math.tan(r) / @res0_u_gnomonic, fn _, acc -> acc * @sqrt7 end)
      {face, r * :math.cos(theta), r * :math.sin(theta)}
    end
  end

  defp nearest_face(point) do
    Tables.face_points()
    |> Enum.with_index()
    |> Enum.reduce(nil, fn {center, face}, best ->
      distance = square_distance(center, point)

      case best do
        {_face, nearest} when nearest <= distance -> best
        _ -> {face, distance}
      end
    end)
  end

  defp square_distance({cx, cy, cz}, {x, y, z}) do
    dx = cx - x
    dy = cy - y
    dz = cz - z
    dx * dx + dy * dy + dz * dz
  end

  defp azimuth(lat1, lng1, lat2, lng2) do
    :math.atan2(
      :math.cos(lat2) * :math.sin(lng2 - lng1),
      :math.cos(lat1) * :math.sin(lat2) -
        :math.sin(lat1) * :math.cos(lat2) * :math.cos(lng2 - lng1)
    )
  end

  defp pos_angle(rads) do
    shifted = if rads < 0.0, do: rads + @two_pi, else: rads
    if rads >= @two_pi, do: shifted - @two_pi, else: shifted
  end

  defp ijk(x, y) do
    x2 = abs(y) / @sin60
    x1 = abs(x) + x2 / 2.0
    m1 = trunc(x1)
    m2 = trunc(x2)
    {i, j} = quantize(m1, m2, x1 - m1, x2 - m2)
    i = if x < 0.0, do: fold(i, j), else: i
    {i, j} = if y < 0.0, do: {i - div(2 * j + 1, 2), -j}, else: {i, j}
    normalize({i, j, 0})
  end

  defp quantize(m1, m2, r1, r2) when r1 < 0.5 do
    if r1 < @one_third do
      if r2 < (1.0 + r1) / 2.0, do: {m1, m2}, else: {m1, m2 + 1}
    else
      {if(1.0 - r1 <= r2 and r2 < 2.0 * r1, do: m1 + 1, else: m1),
       if(r2 < 1.0 - r1, do: m2, else: m2 + 1)}
    end
  end

  defp quantize(m1, m2, r1, r2) do
    cond do
      r1 < @two_thirds ->
        {if(2.0 * r1 - 1.0 < r2 and r2 < 1.0 - r1, do: m1, else: m1 + 1),
         if(r2 < 1.0 - r1, do: m2, else: m2 + 1)}

      r2 < r1 / 2.0 ->
        {m1 + 1, m2}

      true ->
        {m1 + 1, m2 + 1}
    end
  end

  defp fold(i, j) when rem(j, 2) == 0, do: i - 2 * (i - div(j, 2))
  defp fold(i, j), do: i - (2 * (i - div(j + 1, 2)) + 1)

  defp normalize({i, j, k}) do
    {i, j, k} = if i < 0, do: {0, j - i, k - i}, else: {i, j, k}
    {i, j, k} = if j < 0, do: {i - j, 0, k - j}, else: {i, j, k}
    {i, j, k} = if k < 0, do: {i - k, j - k, 0}, else: {i, j, k}
    low = min(i, min(j, k))
    if low > 0, do: {i - low, j - low, k - low}, else: {i, j, k}
  end

  defp encode(face, ijk, 0) do
    if out_of_range?(ijk),
      do: 0,
      else: @base ||| elem(Tables.base_cell(face, ijk), 0) <<< 45
  end

  defp encode(face, ijk, res) do
    {h, center} =
      Enum.reduce((res - 1)..0//-1, {@base ||| res <<< 52, ijk}, fn r, {h, ijk} ->
        {up, down} =
          if rem(r + 1, 2) == 1,
            do: aperture(up_ap7(ijk), &down_ap7/1),
            else: aperture(up_ap7r(ijk), &down_ap7r/1)

        {set_digit(h, r + 1, Map.get(@unit, normalize(sub(ijk, down)), 7)), up}
      end)

    if out_of_range?(center),
      do: 0,
      else: orient(h ||| elem(Tables.base_cell(face, center), 0) <<< 45, face, center, res)
  end

  defp aperture(up, down), do: {up, down.(up)}

  defp orient(h, face, center, res) do
    {cell, rotations} = Tables.base_cell(face, center)

    if Tables.pentagon?(cell) do
      h =
        if leading(h, res) == 1,
          do: rotate(h, res, if(Tables.cw_offset?(cell, face), do: @cw, else: @ccw)),
          else: h

      Enum.reduce(1..rotations//1, h, fn _, acc -> rotate_pentagon(acc, res) end)
    else
      Enum.reduce(1..rotations//1, h, fn _, acc -> rotate(acc, res, @ccw) end)
    end
  end

  defp up_ap7({i, j, k}),
    do: normalize({round((3 * (i - k) - (j - k)) / 7), round((i - k + 2 * (j - k)) / 7), 0})

  defp up_ap7r({i, j, k}),
    do: normalize({round((2 * (i - k) + (j - k)) / 7), round((3 * (j - k) - (i - k)) / 7), 0})

  defp down_ap7({i, j, k}), do: normalize({3 * i + j, 3 * j + k, i + 3 * k})
  defp down_ap7r({i, j, k}), do: normalize({3 * i + k, i + 3 * j, j + 3 * k})
  defp sub({a, b, c}, {d, e, f}), do: {a - d, b - e, c - f}
  defp out_of_range?({i, j, k}), do: i > 2 or j > 2 or k > 2
  defp digit(h, r), do: h >>> ((15 - r) * 3) &&& 7

  defp set_digit(h, r, d),
    do: (h &&& bnot(7 <<< ((15 - r) * 3))) ||| d <<< ((15 - r) * 3)

  defp leading(h, res),
    do: Enum.find_value(1..res//1, 0, fn r -> if digit(h, r) != 0, do: digit(h, r) end)

  defp rotate(h, res, map),
    do:
      Enum.reduce(1..res//1, h, fn r, acc ->
        set_digit(acc, r, Map.get(map, digit(acc, r), digit(acc, r)))
      end)

  defp rotate_pentagon(h, res) do
    {h, _found} =
      Enum.reduce(1..res//1, {h, false}, fn r, {h, found} ->
        h = set_digit(h, r, Map.get(@ccw, digit(h, r), digit(h, r)))

        if not found and digit(h, r) != 0,
          do: {if(leading(h, res) == 1, do: rotate(h, res, @ccw), else: h), true},
          else: {h, found}
      end)

    h
  end
end

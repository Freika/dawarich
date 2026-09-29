defmodule Dawarich.Geo do
  @moduledoc false

  alias Dawarich.RubyFloat

  @earth_radius_km 6371.0

  def distance_m({lat1, lon1}, {lat2, lon2}) do
    {a1, o1, a2, o2} = {rad(lat1), rad(lon1), rad(lat2), rad(lon2)}

    a =
      :math.pow(:math.sin((a2 - a1) / 2), 2) +
        :math.cos(a1) * :math.pow(:math.sin((o2 - o1) / 2), 2) * :math.cos(a2)

    2 * :math.atan2(:math.sqrt(a), :math.sqrt(1 - a)) * @earth_radius_km * 1000
  end

  def path_distance_m(coords), do: coords |> Enum.zip(Enum.drop(coords, 1)) |> pairs_distance_m()

  def pairs_distance_m(pairs) do
    pairs
    |> Enum.map(fn {from, to} -> safe_distance_m(from, to) end)
    |> RubyFloat.sum()
  end

  def safe_distance_m({lat1, lon1} = from, {lat2, lon2} = to) do
    if Enum.all?([lat1, lon1, lat2, lon2], &is_number/1) and abs(lat1) <= 90 and abs(lat2) <= 90 and
         abs(lon1) <= 180 and abs(lon2) <= 180,
       do: distance_m(from, to),
       else: 0.0
  end

  defp rad(degrees), do: degrees * (:math.pi() / 180)
end

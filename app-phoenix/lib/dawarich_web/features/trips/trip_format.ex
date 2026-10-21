defmodule DawarichWeb.TripFormat do
  @moduledoc false

  import DawarichWeb.Translate, only: [t: 3]

  alias DawarichWeb.NumberFormat

  def distance(nil, _factor), do: 0
  def distance(meters, factor), do: round(meters / factor)

  def day_distance(locale, meters, factor) do
    value = meters / factor

    if value < 1,
      do: t(locale, "trips.show.text", %{}),
      else: NumberFormat.with_precision_one(locale, value)
  end

  def duration(locale, []), do: t(locale, "helpers.trips.duration.hours", %{count: 0})

  def duration(locale, parts),
    do:
      Enum.map_join(parts, ", ", fn {key, count} ->
        t(locale, "helpers.trips.duration." <> key, %{count: count})
      end)
end

defmodule Dawarich.SharingTimeZone do
  @moduledoc false
  alias Dawarich.RailsTimeZone

  @source Path.expand("../../priv/rails_time_zone_dst.json", __DIR__)
  @external_resource @source
  @dst @source |> File.read!() |> Jason.decode!() |> Map.fetch!("zones")

  def load(name) do
    {zone, {initial, transitions}} = RailsTimeZone.periods(name)
    dst = Map.fetch!(@dst, zone)
    daylight = MapSet.new(dst["daylight"])
    first = {hd(initial), dst["initial"]}

    changes =
      for {[at, offset, _], index} <- Enum.with_index(Tuple.to_list(transitions)),
          do: {at, {offset, MapSet.member?(daylight, index)}}

    periods = Enum.uniq([first | Enum.map(changes, &elem(&1, 1))])
    indices = periods |> Enum.with_index() |> Map.new()

    %{
      types: List.to_tuple(periods),
      offsets: Enum.map(periods, &elem(&1, 0)) |> Enum.uniq(),
      transitions:
        List.to_tuple(for {at, period} <- changes, do: {at, Map.fetch!(indices, period)})
    }
  end
end

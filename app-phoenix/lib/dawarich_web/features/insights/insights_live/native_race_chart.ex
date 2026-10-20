defmodule DawarichWeb.InsightsLive.NativeRaceChart do
  @moduledoc false
  alias DawarichWeb.LocalizedDate

  def build(race, unit, locale) do
    convert = fn values ->
      Enum.map(values, &Dawarich.RubyFloat.round(Dawarich.Distance.convert(&1, unit) * 1.0, 1))
    end

    current = convert.(race.current)
    previous = race.previous && convert.(race.previous)
    top = ceiling(max(List.last(current), if(previous, do: List.last(previous), else: 0)))
    days = Date.day_of_year(Date.new!(race.year, 12, 31))
    x = fn i -> Dawarich.RubyFloat.round(46 + i / (days - 1) * 662, 1) end
    y = fn v -> Dawarich.RubyFloat.round(12 + (1 - v / top) * 202, 1) end

    line = fn values ->
      Enum.with_index(values)
      |> Enum.map_join(fn {v, i} -> "#{if i == 0, do: "M", else: "L"}#{x.(i)},#{y.(v)}" end)
    end

    last = length(current) - 1

    %{
      current: current,
      previous: previous,
      current_path: line.(current),
      area_path: "#{line.(current)}L#{x.(last)},214L#{x.(0)},214Z",
      previous_path: previous && line.(previous),
      today_x: x.(last),
      today_current_y: y.(List.last(current)),
      today_previous_y: previous && y.(Enum.at(previous, min(last, length(previous) - 1))),
      ticks:
        Enum.map(
          [0, 0.25, 0.5, 0.75, 1],
          &{compact(top * &1), if(&1 in [0, 1], do: round(y.(top * &1)), else: y.(top * &1))}
        ),
      months:
        for(
          month <- 1..12,
          do:
            {LocalizedDate.abbr_month(locale, month),
             x.(Date.day_of_year(Date.new!(race.year, month, 1)) - 1)}
        )
    }
  end

  defp ceiling(value) when value <= 0, do: 1

  defp ceiling(value) do
    magnitude = :math.pow(10, floor(:math.log10(value)))
    Enum.find([1, 2, 2.5, 5, 10], &(value <= &1 * magnitude)) * magnitude
  end

  defp compact(value) when value >= 1000,
    do:
      (:erlang.float_to_binary(Dawarich.RubyFloat.round(value / 1000, 1), decimals: 1)
       |> String.trim_trailing(".0")) <> "k"

  defp compact(value), do: to_string(round(value))
end

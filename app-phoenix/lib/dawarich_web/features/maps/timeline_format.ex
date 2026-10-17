defmodule DawarichWeb.TimelineFormat do
  @moduledoc false

  import DawarichWeb.Translate, only: [t: 3]

  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  @icons %{
    "unknown" => "route",
    "stationary" => "pause",
    "walking" => "footprints",
    "running" => "activity",
    "cycling" => "bike",
    "driving" => "car",
    "bus" => "bus",
    "train" => "train-front",
    "flying" => "plane",
    "boat" => "ship",
    "motorcycle" => "bike"
  }

  def mode_icon(mode), do: Map.get(@icons, to_string(mode), "route")

  def with_gaps(entries, redetected) do
    threshold = if redetected, do: 45, else: 90

    {rows, _covered} =
      Enum.flat_map_reduce(entries, nil, fn entry, covered ->
        gap = if covered, do: Integer.floor_div(entry.start_s - covered.end_s, 60), else: 0
        next = if covered && covered.end_s >= entry.end_s, do: covered, else: entry

        if gap < threshold,
          do: {[entry], next},
          else: {[%{type: "gap", minutes: gap, start_local: covered.end_local}, entry], next}
      end)

    rows
  end

  def display_name(entry, locale) do
    candidates = [entry.name, entry.place && entry.place.name, entry.area && entry.area.name]
    Enum.find(candidates, &Ruby.present?/1) || t(locale, "helpers.timeline.unnamed", %{})
  end

  def name_parts(entry, locale) do
    name = display_name(entry, locale)
    tokens = name |> String.split(",") |> Enum.map(&Ruby.strip/1) |> Enum.reject(&Ruby.blank?/1)

    case merge_numbers(tokens) do
      [] ->
        %{primary: name, secondary: nil}

      [primary | rest] ->
        rest = if length(rest) > 1, do: Enum.drop(rest, -1), else: rest
        secondary = Enum.join(rest, ", ")
        %{primary: primary, secondary: if(secondary == "", do: nil, else: secondary)}
    end
  end

  def search_tokens(entry) do
    place = entry.place || %{}
    area = entry.area || %{}

    [entry.name, entry.editable_name, place[:name], place[:city], place[:country], area[:name]]
    |> Kernel.++(Enum.map(entry.tags, & &1.name))
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
    |> String.downcase()
  end

  def dwell(locale, minutes) do
    minutes = minutes || 0
    {hours, rest} = {div(minutes, 60), rem(minutes, 60)}

    cond do
      minutes <= 0 -> t(locale, "units.minutes_compact", %{value: 0})
      rest == 0 and hours > 0 -> t(locale, "units.hours_compact", %{value: hours})
      hours == 0 -> t(locale, "units.minutes_compact", %{value: rest})
      true -> t(locale, "units.hours_minutes_compact", %{hours: hours, minutes: rest})
    end
  end

  def duration_short(locale, seconds) do
    total = trunc(seconds || 0)
    days = Integer.floor_div(total, 86_400)
    hours = total |> Integer.mod(86_400) |> Integer.floor_div(3600)
    minutes = total |> Integer.mod(3600) |> Integer.floor_div(60)

    cond do
      total == 0 -> t(locale, "units.minutes_compact", %{value: 0})
      days > 0 and hours > 0 -> t(locale, "units.days_hours_compact", %{days: days, hours: hours})
      days > 0 -> t(locale, "units.days_compact", %{value: days})
      hours > 0 -> t(locale, "units.hours_minutes_compact", %{hours: hours, minutes: minutes})
      true -> t(locale, "units.minutes_compact", %{value: minutes})
    end
  end

  def leg_extra(seconds) do
    minutes = Integer.floor_div(trunc(seconds || 0), 60)
    if minutes <= 0, do: 0, else: (:math.sqrt(minutes) * 3.2) |> round() |> min(80) |> max(0)
  end

  def all_day?(entry),
    do:
      (entry.duration || 0) >= 1380 or
        (entry.start_local.hour == 0 and entry.end_s - entry.start_s >= 82_800)

  def subdued?(entry, gating), do: gated?(entry, gating, "medium")
  def low_confidence?(entry, gating), do: gated?(entry, gating, "low")

  def cell_classes(cell) do
    bucket = cell.heat_bucket

    (["cal-cell", "heat-#{bucket}"] ++
       if(cell.suggested_count > 0, do: ["has-suggestions"], else: []) ++
       if(cell.in_month, do: [], else: ["out-of-month"]) ++
       if(cell.disabled, do: ["disabled"], else: []) ++
       [if(bucket >= 3, do: "cal-cell--light-text", else: "cal-cell--dark-text")])
    |> Enum.join(" ")
  end

  def bounds_json(nil), do: ""

  def bounds_json(bounds),
    do:
      {:object,
       [
         {"sw_lat", bounds.sw_lat},
         {"sw_lng", bounds.sw_lng},
         {"ne_lat", bounds.ne_lat},
         {"ne_lng", bounds.ne_lng}
       ]}
      |> Ruby.json()
      |> IO.iodata_to_binary()

  defp gated?(entry, gating, band),
    do: gating and (entry.status || "confirmed") != "confirmed" and entry.confidence_band == band

  defp merge_numbers(tokens) do
    Enum.reduce(tokens, [], fn token, merged ->
      if merged != [] and token =~ ~r/\A\d+[a-z]?\z/i,
        do: List.update_at(merged, -1, &(&1 <> " " <> token)),
        else: merged ++ [token]
    end)
  end
end

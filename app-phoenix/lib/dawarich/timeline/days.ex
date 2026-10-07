defmodule Dawarich.Timeline.Days do
  @moduledoc false

  alias Dawarich.{Distance, RubyFloat}
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias Dawarich.Timeline.DayRows

  @max_range 2_678_400
  @chip_min 0.5

  def load(user, window, window_now, repo \\ Dawarich.Repo) do
    {:ok, from, _} = DateTime.from_iso8601(window.start)
    {:ok, to, _} = DateTime.from_iso8601(window.end)

    range =
      {DateTime.to_unix(from, :microsecond) / 1_000_000,
       DateTime.to_unix(to, :microsecond) / 1_000_000}

    if elem(range, 1) - elem(range, 0) > @max_range do
      %{days: [], redetected: false}
    else
      rows = DayRows.fetch(user, range, {window.start_date, window.end_date}, window_now, repo)
      %{days: build(rows, unit(Dawarich.UserSettings.get(user))), redetected: rows.redetected}
    end
  end

  def unit(settings),
    do: get_in(Dawarich.UserSettings.safe(settings), ["maps", "distance_unit"]) || "km"

  def distance(nil, _unit), do: 0.0
  def distance(meters, unit), do: RubyFloat.round(Distance.convert(meters, unit), 1)

  def speed(kmh, _unit) when kmh == 0, do: 0.0
  def speed(kmh, "mi"), do: RubyFloat.round(kmh * 0.621371, 1)
  def speed(kmh, _unit), do: RubyFloat.round(kmh * 1.0, 1)

  def build(%{visits: [], tracks: []}, _unit), do: []

  def build(rows, unit) do
    rows
    |> buckets()
    |> Enum.sort_by(&elem(&1, 0), Date)
    |> Enum.map(fn {date, bucket} -> day(date, bucket, rows, unit) end)
  end

  defp buckets(rows) do
    visits =
      Enum.reduce(rows.visits, %{}, fn visit, acc ->
        if within?(visit.day, rows),
          do: Map.update(acc, visit.day, bucket([visit]), &%{&1 | visits: &1.visits ++ [visit]}),
          else: acc
      end)

    Enum.reduce(rows.tracks, visits, fn track, acc ->
      Enum.reduce(track.shares, acc, fn {date, share}, acc ->
        if within?(date, rows),
          do: Map.update(acc, date, add(bucket([]), track, share), &add(&1, track, share)),
          else: acc
      end)
    end)
  end

  defp bucket(visits), do: %{visits: visits, tracks: [], shares: %{}}

  defp add(bucket, track, share),
    do: %{
      bucket
      | tracks: bucket.tracks ++ [track],
        shares: Map.put(bucket.shares, track.id, share)
    }

  defp within?(date, rows),
    do: Date.compare(date, rows.first) != :lt and Date.compare(date, rows.last) != :gt

  defp day(date, bucket, rows, unit) do
    %{
      date: Date.to_iso8601(date),
      summary: summary(bucket, rows, unit),
      bounds: bounds(bucket.visits, Map.get(rows.extents, date), rows),
      entries: entries(date, bucket, rows, unit)
    }
  end

  defp entries(date, bucket, rows, unit) do
    {day_start, day_end} = Map.fetch!(rows.midnights, date)
    visits = Enum.map(bucket.visits, &entry(&1, rows))

    journeys =
      Enum.map(
        bucket.tracks,
        &journey_entry(&1, date, Map.fetch!(bucket.shares, &1.id), rows, unit)
      )

    Enum.sort_by(visits ++ journeys, fn entry ->
      started = entry.start_s * 1_000_000

      anchor =
        if entry[:continuation_of_date],
          do: max(min(entry.end_s * 1_000_000, day_end), day_start),
          else: started

      {anchor, started}
    end)
  end

  def entry(visit, rows) do
    place = visit.place_id && Map.fetch!(rows.places, visit.place_id)

    entry = %{
      type: "visit",
      visit_id: visit.id,
      name: visit.name,
      editable_name: visit.name,
      status: visit.status,
      confidence_band: band(visit.confidence),
      place_id: visit.place_id,
      point_count: Map.get(rows.counts, visit.id, 0),
      tags: if(place, do: Map.get(rows.tags, visit.place_id, []), else: []),
      started_at: visit.started_at,
      ended_at: visit.ended_at,
      start_s: visit.start_s,
      end_s: visit.end_s,
      start_local: visit.start_local,
      end_local: visit.end_local,
      duration: visit.duration,
      place: place,
      area: visit.area_id && Map.fetch!(rows.areas, visit.area_id)
    }

    if visit.status == "suggested",
      do: Map.put(entry, :suggested_places, suggested(visit, place, rows)),
      else: entry
  end

  defp suggested(visit, place, rows) do
    candidates =
      List.wrap(place) ++
        Enum.map(Map.get(rows.suggestions, visit.id, []), &Map.fetch!(rows.places, &1))

    {picked, _seen} =
      Enum.reduce(candidates, {[], MapSet.new()}, fn candidate, {picked, seen} ->
        key = candidate.name |> Ruby.strip() |> String.downcase()

        if key == "" or MapSet.member?(seen, key),
          do: {picked, seen},
          else:
            {picked ++
               [%{id: candidate.id, name: candidate.name, lat: candidate.lat, lng: candidate.lng}],
             MapSet.put(seen, key)}
      end)

    picked
  end

  defp journey_entry(track, date, share, rows, unit) do
    continuation = date != track.start_day
    moving = Map.get(rows.moving, track.id)

    %{
      type: "journey",
      track_id: track.id,
      started_at: track.started_at,
      ended_at: track.ended_at,
      start_s: track.start_s,
      end_s: track.end_s,
      start_local: track.start_local,
      end_local: track.end_local,
      duration: track.duration,
      distance: distance(track.distance, unit),
      distance_unit: unit,
      dominant_mode: track.mode,
      avg_speed: speed(track.avg_speed || 0.0, unit),
      speed_unit: if(unit == "mi", do: "mph", else: "km/h"),
      elevation_gain: track.elevation_gain,
      elevation_loss: track.elevation_loss,
      continuation_of_date: if(continuation, do: Date.to_iso8601(track.start_day)),
      day_distance: if(continuation, do: distance((track.distance || 0) * share, unit)),
      day_duration: if(continuation, do: round((track.duration || 0) * share)),
      moving_duration: if(continuation and moving != nil, do: round(moving * share), else: moving)
    }
  end

  defp summary(%{visits: visits, tracks: tracks, shares: shares}, rows, unit) do
    share = &Map.fetch!(shares, &1.id)
    statuses = Enum.frequencies_by(visits, & &1.status)
    meters = RubyFloat.sum(for track <- tracks, do: (track.distance || 0) * share.(track))

    moving =
      RubyFloat.sum(
        for track <- tracks, track.mode != "stationary", do: (track.duration || 0) * share.(track)
      )

    %{
      total_distance: distance(meters, unit),
      distance_unit: unit,
      places_visited:
        visits |> Enum.map(& &1.place_id) |> Enum.reject(&is_nil/1) |> Enum.uniq() |> length(),
      time_moving_minutes: round(moving / 60.0),
      time_stationary_minutes: visits |> Enum.map(& &1.duration) |> Enum.sum(),
      suggested_count: Map.get(statuses, "suggested", 0),
      confirmed_count: Map.get(statuses, "confirmed", 0),
      declined_count: Map.get(statuses, "declined", 0),
      mode_distances: modes(tracks, shares, rows, unit)
    }
  end

  defp modes(tracks, shares, rows, unit) do
    ids = MapSet.new(tracks, & &1.id)

    {order, totals} =
      Enum.reduce(rows.mode_meters, {[], %{}}, fn {track_id, mode, meters}, {order, totals} ->
        if MapSet.member?(ids, track_id) do
          value = meters * 1.0 * Map.fetch!(shares, track_id)
          order = if Map.has_key?(totals, mode), do: order, else: order ++ [mode]
          {order, Map.update(totals, mode, 0.0 + value, &(&1 + value))}
        else
          {order, totals}
        end
      end)

    order
    |> Enum.map(&{&1, distance(Map.fetch!(totals, &1), unit)})
    |> Enum.reject(fn {_mode, value} -> value < @chip_min end)
    |> Enum.sort_by(fn {_mode, value} -> -value end)
  end

  defp bounds(visits, extent, rows) do
    places = for visit <- visits, visit.place_id, do: Map.fetch!(rows.places, visit.place_id)

    lats =
      Enum.map(places, & &1.lat) ++ if(extent, do: [extent.min_lat, extent.max_lat], else: [])

    lngs =
      Enum.map(places, & &1.lng) ++ if(extent, do: [extent.min_lng, extent.max_lng], else: [])

    if lats == [],
      do: nil,
      else: %{
        sw_lat: Enum.min(lats),
        sw_lng: Enum.min(lngs),
        ne_lat: Enum.max(lats),
        ne_lng: Enum.max(lngs)
      }
  end

  defp band(nil), do: nil
  defp band(confidence) when confidence >= 70, do: "high"
  defp band(confidence) when confidence >= 40, do: "medium"
  defp band(_confidence), do: "low"
end

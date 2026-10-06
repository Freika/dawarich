defmodule Dawarich.EnhancedImport.SegmentWriter do
  @moduledoc false
  alias Dawarich.Tracks.{Builder, Points}
  alias Dawarich.Transportation.Segments

  def upsert(repo, id, item, first, last) do
    points = Points.of_track(repo, id)

    indices =
      Enum.with_index(points)
      |> Enum.filter(fn {p, _} -> p.timestamp >= first and p.timestamp <= last end)
      |> Enum.map(&elem(&1, 1))

    indices =
      if item["end_index"] > item["start_index"],
        do: Enum.slice(indices, item["start_index"]..item["end_index"]),
        else: indices

    segments = rows(repo, id)

    keep =
      Enum.filter(
        segments,
        &(&1.corrected != nil or
            (&1.source in ~w(google_phone_takeout google_semantic_history polarsteps) and
               &1.source != item["source_label"]))
      )

    covered = Enum.flat_map(keep, &covered(&1, points)) |> MapSet.new()

    pieces =
      indices
      |> Enum.reject(&MapSet.member?(covered, &1))
      |> Enum.chunk_by(fn i -> i - Enum.find_index(indices, &(&1 == i)) end)
      |> contiguous()

    if pieces == [] do
      false
    else
      existing =
        Enum.all?(pieces, fn piece ->
          Enum.any?(
            segments,
            &(&1.first == Enum.at(points, hd(piece)).timestamp and
                &1.source == item["source_label"])
          )
        end)

      unless existing do
        clear(repo, id, points, indices, segments -- keep)

        for piece <- pieces do
          data =
            geometry(points, piece)
            |> Map.merge(%{
              mode: item["transportation_mode"],
              confidence: confidence(item["confidence"]),
              confidence_score: nil,
              source: item["source_label"]
            })

          Segments.insert!(repo, id, [data])
        end
      end

      true
    end
  end

  defp contiguous(pieces) do
    pieces
    |> List.flatten()
    |> Enum.chunk_while(
      [],
      fn
        i, [] -> {:cont, [i]}
        i, [previous | _] = acc when i == previous + 1 -> {:cont, [i | acc]}
        i, acc -> {:cont, Enum.reverse(acc), [i]}
      end,
      fn acc -> {:cont, Enum.reverse(acc), []} end
    )
  end

  defp clear(repo, id, points, indices, segments) do
    first = hd(indices)
    last = List.last(indices)

    for s <- segments do
      covered = covered(s, points)

      overlap =
        if s.first,
          do:
            s.first < Enum.at(points, last).timestamp and
              s.last > Enum.at(points, first).timestamp,
          else: s.start_index <= last and s.end_index >= first

      if overlap do
        outside =
          [Enum.filter(covered, &(&1 < first)), Enum.filter(covered, &(&1 > last))]
          |> Enum.filter(&(length(&1) >= 2))

        repo.query!("DELETE FROM track_segments WHERE id=$1", [s.id], log: false)

        for piece <- outside do
          data =
            geometry(points, piece)
            |> Map.merge(%{
              mode: Segments.int_to_mode(s.mode),
              confidence: Enum.at(~w(low medium high), s.confidence || 0),
              confidence_score: s.score,
              source: s.source
            })

          Segments.insert!(repo, id, [data])
        end
      end
    end
  end

  defp rows(repo, id) do
    keys = ~w(id first last start_index end_index mode confidence score corrected source)a

    repo.query!(
      "SELECT id,extract(epoch FROM start_at)::bigint,extract(epoch FROM end_at)::bigint,start_index,end_index,transportation_mode,confidence,confidence_score,corrected_at,source FROM track_segments WHERE track_id=$1 ORDER BY id",
      [id],
      log: false
    ).rows
    |> Enum.map(&Map.new(Enum.zip(keys, &1)))
  end

  defp covered(s, points) do
    Enum.with_index(points)
    |> Enum.filter(fn {p, i} ->
      if s.first && s.last,
        do: p.timestamp >= s.first and p.timestamp <= s.last,
        else: i >= s.start_index and i <= s.end_index
    end)
    |> Enum.map(&elem(&1, 1))
  end

  defp geometry(points, indices) do
    points = Enum.map(indices, &Enum.at(points, &1))
    first = hd(points)
    last = List.last(points)
    distance = Dawarich.Geo.path_distance_m(Builder.coords(points)) |> round()

    speed =
      points
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.flat_map(fn [a, b] ->
        if b.timestamp > a.timestamp,
          do: [
            Dawarich.Geo.path_distance_m(Builder.coords([a, b])) / (b.timestamp - a.timestamp) *
              3.6
          ],
          else: []
      end)
      |> Enum.max(fn -> 0.0 end)

    %{
      start_at: first.timestamp,
      end_at: last.timestamp,
      path_wkt: if(length(points) > 1, do: Builder.path_wkt(points)),
      distance: distance,
      duration: last.timestamp - first.timestamp,
      avg_speed: Builder.avg_speed_kmh(distance, last.timestamp - first.timestamp),
      max_speed: speed
    }
  end

  defp confidence(value) do
    text = to_string(value || "") |> String.trim() |> String.downcase()

    number =
      case Float.parse(text) do
        {n, _} -> n
        _ -> 0
      end

    cond do
      text in ~w(high medium low) -> text
      (number >= 0.8 and number <= 1) or number >= 80 -> "high"
      (number >= 0.5 and number < 0.8) or number >= 50 -> "medium"
      true -> "low"
    end
  end
end

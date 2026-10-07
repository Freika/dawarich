defmodule Dawarich.EnhancedImport.TrackWriter do
  @moduledoc false
  alias Dawarich.Tracks.{Builder, Points}
  alias Dawarich.Transportation.{DominantMode, Segments}

  def reset(repo, import) do
    lease = %{
      repo: repo,
      id: import.id,
      user: import.user_id,
      job: import.job,
      extraction_fence: import.fence
    }

    Dawarich.Imports.DestroyExtraction.reset_segments(lease, import.source)
  end

  def upsert(repo, import, item, trust) do
    first = epoch(item["start_at"])
    last = epoch(item["end_at"])
    [[settings]] = query(repo, "SELECT settings FROM users WHERE id=$1", [import.user_id])
    user = %{id: import.user_id, settings: settings || %{}}
    id = existing(repo, import, item["tracker_id"])

    id =
      if id do
        query(repo, "DELETE FROM track_segments WHERE track_id=$1 AND corrected_at IS NULL", [id])
        unless trust, do: Segments.reclassify!(repo, id, user.settings)
        id
      else
        build(repo, user, import, item, first, last, trust)
      end

    if id do
      written = if trust, do: source_segments(repo, id, item, first, last), else: 0
      mode = repo |> Segments.load_segments_for_dominant_mode!(id) |> DominantMode.pick()

      query(repo, "UPDATE tracks SET dominant_mode=$2 WHERE id=$1", [
        id,
        Segments.mode_to_int(mode || "unknown")
      ])

      {id, written}
    end
  end

  defp build(repo, user, import, item, first, last, trust) do
    ids =
      query(
        repo,
        "SELECT id FROM points WHERE user_id=$1 AND import_id=$2 AND track_id IS NULL AND timestamp BETWEEN $3 AND $4 ORDER BY timestamp,id FOR UPDATE",
        [user.id, import.id, first, last]
      )
      |> List.flatten()

    groups =
      Points.claim_orphans!(repo, user.id, ids, true)
      |> Enum.group_by(& &1.tracker_id)
      |> Map.values()

    points = if groups == [], do: [], else: Enum.min_by(groups, &{-length(&1), hd(&1).timestamp})

    case Builder.create_track!(repo, user, points, item["distance_m"] || 0,
           tracker_id: item["tracker_id"],
           skip_segment_detection: trust
         ) do
      {:ok, track} ->
        query(repo, "UPDATE tracks SET import_id=$2 WHERE id=$1", [track.id, import.id])
        track.id

      nil ->
        case query(
               repo,
               "SELECT t.id FROM tracks t WHERE t.user_id=$1 AND EXISTS(SELECT 1 FROM points p WHERE p.track_id=t.id AND p.user_id=$1 AND p.import_id=$2 AND p.timestamp BETWEEN $3 AND $4) ORDER BY t.id FOR UPDATE OF t",
               [user.id, import.id, first, last]
             ) do
          [[id]] -> id
          _ -> nil
        end
    end
  end

  defp existing(repo, import, tracker) do
    case query(
           repo,
           "SELECT id FROM tracks WHERE user_id=$1 AND tracker_id=$2 ORDER BY id LIMIT 1 FOR UPDATE",
           [import.user_id, tracker]
         ) do
      [[id]] -> id
      [] -> nil
    end
  end

  defp source_segments(repo, id, item, first, last) do
    Enum.count(
      item["segments"],
      &Dawarich.EnhancedImport.SegmentWriter.upsert(repo, id, &1, first, last)
    )
  end

  defp epoch(text), do: text |> DateTime.from_iso8601() |> elem(1) |> DateTime.to_unix()
  defp query(repo, sql, params), do: repo.query!(sql, params, log: false).rows
end

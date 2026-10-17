defmodule Dawarich.Imports.DestroyExtraction do
  @moduledoc false
  alias Dawarich.Imports.{DestroyLease, DestroyEffects}

  @sources ~w(google_semantic_history owntracks google_records google_phone_takeout gpx immich_api geojson photoprism_api user_data_archive kml csv tcx fit polarsteps google_photos mobile_photo_library)

  def call(lease, source) do
    places =
      effect!(lease, fn ->
        query(lease, "SELECT id FROM places WHERE import_id=$1 AND user_id=$2", [
          lease.id,
          lease.user
        ])
        |> List.flatten()
      end)

    batches(lease, "visits", fn rows -> destroy_visits(lease, rows) end)
    batches(lease, "tracks", fn rows -> destroy_tracks(lease, rows) end)
    orphaned_places(lease, places)
    reset_segments(lease, source)

    effect!(lease, fn ->
      query(
        lease,
        "UPDATE imports SET additional_data_extraction_status=0,additional_data_extraction='{}' WHERE id=$1 AND user_id=$2",
        [lease.id, lease.user]
      )
    end)
  end

  defp batches(lease, table, fun) when table in ["visits", "tracks"] do
    count =
      effect!(lease, fn ->
        columns =
          if table == "visits",
            do: "id,place_id,started_at,demo",
            else:
              "id,floor(extract(epoch FROM start_at))::bigint,floor(extract(epoch FROM end_at))::bigint"

        rows =
          query(
            lease,
            "SELECT #{columns} FROM #{table} WHERE import_id=$1 AND user_id=$2 ORDER BY id LIMIT 500 FOR UPDATE",
            [lease.id, lease.user]
          )

        if rows != [], do: fun.(rows)
        length(rows)
      end)

    if count > 0, do: batches(lease, table, fun), else: :ok
  end

  defp destroy_visits(lease, rows) do
    ids = Enum.map(rows, &hd/1)

    query(
      lease,
      "UPDATE points SET visit_id=NULL WHERE visit_id=ANY($1::bigint[]) AND user_id=$2",
      [ids, lease.user]
    )

    query(lease, "DELETE FROM place_visits WHERE visit_id=ANY($1::bigint[])", [ids])

    query(
      lease,
      "DELETE FROM notes WHERE attachable_type='Visit' AND attachable_id=ANY($1::bigint[]) AND user_id=$2",
      [ids, lease.user]
    )

    query(lease, "DELETE FROM visits WHERE id=ANY($1::bigint[]) AND user_id=$2", [ids, lease.user])

    DestroyEffects.visits!(lease, rows)
  end

  defp destroy_tracks(lease, rows) do
    ids = Enum.map(rows, &hd/1)

    query(
      lease,
      "UPDATE points SET track_id=NULL WHERE track_id=ANY($1::bigint[]) AND user_id=$2",
      [ids, lease.user]
    )

    query(lease, "DELETE FROM track_segments WHERE track_id=ANY($1::bigint[])", [ids])

    query(
      lease,
      "DELETE FROM shared_links WHERE resource_type=1 AND resource_id=ANY($1::bigint[]) AND user_id=$2",
      [ids, lease.user]
    )

    query(lease, "DELETE FROM tracks WHERE id=ANY($1::bigint[]) AND user_id=$2", [ids, lease.user])

    Dawarich.Tracks.Effects.write!(lease.repo, lease.user, %{
      destroyed: ids,
      stamps: Enum.flat_map(rows, fn [_id, a, b] -> [a, b] end)
    })
  end

  defp orphaned_places(_lease, []), do: :ok

  defp orphaned_places(lease, ids) do
    deleted =
      effect!(lease, fn ->
        rows =
          query(
            lease,
            "SELECT p.id FROM places p WHERE p.id=ANY($1::bigint[]) AND p.user_id=$2 AND NOT EXISTS(SELECT 1 FROM visits v WHERE v.place_id=p.id) ORDER BY p.id LIMIT 500 FOR UPDATE",
            [ids, lease.user]
          )

        selected = List.flatten(rows)

        if selected != [] do
          query(
            lease,
            "DELETE FROM notes WHERE attachable_type='Place' AND attachable_id=ANY($1::bigint[]) AND user_id=$2",
            [selected, lease.user]
          )

          query(
            lease,
            "DELETE FROM taggings WHERE taggable_type='Place' AND taggable_id=ANY($1::bigint[])",
            [selected]
          )

          query(lease, "DELETE FROM place_visits WHERE place_id=ANY($1::bigint[])", [selected])

          query(lease, "DELETE FROM places WHERE id=ANY($1::bigint[]) AND user_id=$2", [
            selected,
            lease.user
          ])
        end

        selected
      end)

    if deleted != [], do: orphaned_places(lease, ids -- deleted), else: :ok
  end

  def reset_segments(lease, source) do
    label = if is_integer(source) and source >= 0, do: Enum.at(@sources, source)

    effect!(lease, fn ->
      tracks =
        query(
          lease,
          "DELETE FROM track_segments s WHERE s.corrected_at IS NULL AND s.source IS NOT DISTINCT FROM $3 AND s.track_id IN(SELECT t.id FROM tracks t WHERE t.user_id=$2 AND t.import_id IS DISTINCT FROM $1 AND t.id IN(SELECT track_id FROM points WHERE import_id=$1 AND user_id=$2 AND track_id IS NOT NULL)) RETURNING track_id",
          [lease.id, lease.user, label]
        )
        |> List.flatten()
        |> Enum.uniq()

      if tracks != [],
        do: DestroyEffects.callback!(lease, "reclassify_tracks", %{"track_ids" => tracks})
    end)
  end

  defp effect!(%{extraction_fence: fence}, fun), do: fence.(fun)
  defp effect!(lease, fun), do: DestroyLease.effect!(lease, fun)

  defp query(lease, sql, params), do: lease.repo.query!(sql, params, log: false).rows
end

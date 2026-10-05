defmodule Dawarich.RailsCommands do
  @moduledoc false

  @closure_kinds ~w(
    achievements.bulk_check_leaf achievements.check airtrail_stats cache.preheat_sweep
    cache.preheat_user digests.calculate_month digests.calculate_year digests.email_month
    digests.email_year enhanced_import_card exports.points_created exports.purge
    family_location_request_mail geocode_recent_points geocoding.reverse_point imports.destroy_achievements
    imports.destroy_callbacks imports.destroy_complete imports.destroy_requested imports.destroy_stats
    imports.destroy_status imports.destroy_terminal imports.extraction_destroy_requested imports.extraction_requested
    imports.normal_resume imports.postprocessing_step imports.prepare_download imports.prepared_download_purge
    imports.progress imports.resume imports.upload_created integrations.airtrail_flights
    integrations.teslamate_sync integrations.trek_sync mail.family_lapse place_name_fetch
    places_bulk_name_fetch places_delete_if_orphan places_orphan_cleanup points.anomaly_backfill
    points.anomaly_filter points.anomaly_recalculate points.anomaly_stats points.live_broadcast
    points.tile_epoch points.web_destroy_follow_up posters.created posters.progress
    posters.purge release.anomalies release.anomalies_user release.per_tracker
    release_achievements_bulk_check release_null_island_follow_up release_reclassify_tracks release_user_redetect reverse_geocode_place
    route_videos.attachment_job schedule_untracked_tracks share_management.live_revoked stats.caches_invalidated
    stats.calculate_month stats.full_recalculation tracks.backfill tracks.realtime
    tracks_changed tracks_generate_range tracks_realtime_retrigger tracks_throttled_backfill
    transport_progress trips.calculate users.export_data users.import_data
    users.recalculate_data visit_months_changed visits.realtime visits.suggest
    visits.web_redetect
  )

  def closure_kinds, do: @closure_kinds

  def insert!(
        repo,
        "release_achievements_bulk_check" = kind,
        %{
          "job_id" => job_id,
          "options" => %{"notify" => notify, "force" => force, "stale_only" => stale} = options,
          "run_at" => run_at
        } = payload
      )
      when map_size(payload) == 3 and map_size(options) == 3 and is_binary(job_id) and
             is_binary(run_at) and is_boolean(notify) and is_boolean(force) and is_boolean(stale) do
    with {:ok, _} <- Ecto.UUID.cast(job_id),
         {:ok, _, _} <- DateTime.from_iso8601(run_at) do
      insert_row!(repo, kind, payload)
    else
      _ -> raise ArgumentError, "invalid release bulk payload"
    end
  end

  def insert!(_repo, "release_achievements_bulk_check", _payload),
    do: raise(ArgumentError, "invalid release bulk payload")

  def insert!(repo, kind, %{"user_id" => user_id} = payload)
      when is_binary(kind) and is_integer(user_id),
      do: insert_row!(repo, kind, payload)

  def insert!(
        repo,
        "cache.preheat_sweep",
        %{"time_zone" => zone, "source_job_id" => uuid, "run_at" => at} = payload
      )
      when is_binary(zone) and is_binary(uuid) and byte_size(uuid) == 36 and is_integer(at) and
             map_size(payload) == 3 do
    if match?({:ok, _}, Ecto.UUID.cast(uuid)),
      do: insert_row!(repo, "cache.preheat_sweep", payload),
      else: raise(ArgumentError, "invalid source job UUID")
  end

  def insert!(repo, "places_bulk_name_fetch" = kind, payload)
      when is_map(payload) and map_size(payload) == 0 do
    insert_row!(repo, kind, payload)
  end

  defp insert_row!(repo, kind, payload) do
    repo.query!(
      "INSERT INTO phoenix.rails_commands (kind, payload) VALUES ($1, $2::text::jsonb)",
      [kind, Dawarich.RubyJson.encode_exact!(payload)],
      log: false
    )

    :ok
  end
end

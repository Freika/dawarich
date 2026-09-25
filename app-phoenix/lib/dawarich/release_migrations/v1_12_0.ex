defmodule Dawarich.ReleaseMigrations.V1_12_0 do
  @moduledoc false
  @behaviour Dawarich.ReleaseMigration

  import Dawarich.ReleaseMigration

  @track_segment_columns [
    {"start_at", "timestamptz"},
    {"end_at", "timestamptz"},
    {"path", "geometry(LINESTRING,4326)"},
    {"confidence_score", "float"}
  ]

  @declined_visit_ids """
  SELECT id FROM visits WHERE id > $1 AND status = 2 ORDER BY id LIMIT 10000
  """

  @soft_delete_visits """
  UPDATE visits SET deleted_at = NOW() WHERE id = ANY($1) AND deleted_at IS NULL
  """

  @impl true
  def release, do: "1.12.0"

  @impl true
  def data_versions, do: []

  @impl true
  def steps do
    [
      {"20260804085722", &add_time_anchoring_to_track_segments/1, transaction: false},
      {"20260804085723", &enqueue_track_segment_time_anchor_backfill/1},
      {"20260804093200", &remove_transportation_threshold_settings/1},
      {"20260805120000", &add_deleted_at_to_visits/1},
      {"20260805120001", &soft_delete_declined_visits/1, transaction: false},
      {"20260808120000", &add_detection_version_to_visits/1},
      {"20260809085900", &reset_visits_redetected_at_for_detection_v3/1},
      {"20260809085930", &default_visits_redetected_at_for_new_accounts/1},
      {"20260809090000", &enqueue_visits_fleet_redetection/1},
      {"20260809090100", &remove_retired_visit_detection_settings/1}
    ]
  end

  defp add_time_anchoring_to_track_segments(repo) do
    for {name, type} <- @track_segment_columns, not column?(repo, "track_segments", name) do
      sql!(repo, ~s|ALTER TABLE "track_segments" ADD "#{name}" #{type};|)
    end

    sql!(repo, ~S"""
    ALTER TABLE "track_segments" ALTER COLUMN "start_index" DROP NOT NULL;
    """)

    sql!(repo, ~S"""
    ALTER TABLE "track_segments" ALTER COLUMN "end_index" DROP NOT NULL;
    """)

    sql!(repo, ~S"""
    DO $$ BEGIN IF EXISTS ( SELECT 1 FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid WHERE c.relname = 'idx_track_segments_track_start_at_unique' AND NOT i.indisvalid ) THEN EXECUTE 'DROP INDEX idx_track_segments_track_start_at_unique'; END IF; END $$;
    """)

    sql!(repo, ~S"""
    CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS "idx_track_segments_track_start_at_unique" ON "track_segments" ("track_id", "start_at") WHERE start_at IS NOT NULL;
    """)
  end

  defp enqueue_track_segment_time_anchor_backfill(_repo),
    do: {:jobs, [job("TrackSegments::TimeAnchorBackfillJob")]}

  defp remove_transportation_threshold_settings(repo) do
    sql!(repo, ~S"""
    UPDATE users SET settings = settings - 'transportation_thresholds' - 'transportation_expert_thresholds' - 'transportation_expert_mode' WHERE settings ?| array['transportation_thresholds','transportation_expert_thresholds','transportation_expert_mode'];
    """)
  end

  defp add_deleted_at_to_visits(repo) do
    sql!(repo, ~S"""
    ALTER TABLE "visits" ADD "deleted_at" timestamp(6);
    """)
  end

  defp soft_delete_declined_visits(repo), do: soft_delete_declined_visits_after(repo, 0)

  defp soft_delete_declined_visits_after(repo, last_id) do
    case repo.query!(@declined_visit_ids, [last_id], log: false) do
      %{rows: []} ->
        :ok

      %{rows: rows} ->
        ids = List.flatten(rows)
        repo.query!(@soft_delete_visits, [ids], log: false)
        soft_delete_declined_visits_after(repo, List.last(ids))
    end
  end

  defp add_detection_version_to_visits(repo) do
    unless column?(repo, "visits", "detection_version") do
      sql!(repo, ~S"""
      ALTER TABLE "visits" ADD "detection_version" smallint;
      """)
    end
  end

  defp reset_visits_redetected_at_for_detection_v3(repo) do
    sql!(repo, ~S"""
    UPDATE users SET visits_redetected_at = NULL WHERE visits_redetected_at IS NOT NULL;
    """)
  end

  defp default_visits_redetected_at_for_new_accounts(repo) do
    sql!(repo, ~S"""
    ALTER TABLE "users" ALTER COLUMN "visits_redetected_at" SET DEFAULT CURRENT_TIMESTAMP;
    """)
  end

  defp enqueue_visits_fleet_redetection(_repo) do
    if self_hosted?() and String.trim(System.get_env("SKIP_VISITS_FLEET_REDETECT", "")) == "",
      do: {:jobs, [job("Visits::FleetRedetectJob")]}
  end

  defp remove_retired_visit_detection_settings(repo) do
    sql!(repo, ~S"""
    UPDATE users SET settings = settings - 'stay_max_gap_minutes' - 'visit_density_fill_enabled' WHERE settings ?| array['stay_max_gap_minutes','visit_density_fill_enabled'];
    """)
  end
end

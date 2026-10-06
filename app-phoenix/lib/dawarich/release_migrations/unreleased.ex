defmodule Dawarich.ReleaseMigrations.Unreleased do
  @moduledoc false
  @behaviour Dawarich.ReleaseMigration

  import Dawarich.ReleaseMigration

  @import_initial_delay_seconds 2 * 60
  @import_delay_seconds 10

  @job_outbox_sql ~S"""
  CREATE TABLE job_outbox (
    event_id uuid PRIMARY KEY,
    command_type character varying NOT NULL,
    command_version integer NOT NULL,
    payload jsonb NOT NULL,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    aggregate_id bigint,
    dedupe_key character varying,
    scheduled_at timestamp with time zone NOT NULL,
    state character varying NOT NULL DEFAULT 'pending',
    oban_job_id bigint,
    error_code character varying,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    dispatched_at timestamp with time zone,
    CONSTRAINT job_outbox_command_version_positive CHECK (command_version > 0),
    CONSTRAINT job_outbox_payload_object CHECK (jsonb_typeof(payload) = 'object' AND octet_length(payload::text) <= 8192),
    CONSTRAINT job_outbox_state_known CHECK (state IN ('pending', 'dispatched', 'quarantined'))
  );
  CREATE INDEX index_job_outbox_on_due ON job_outbox (scheduled_at, event_id) WHERE state = 'pending';
  CREATE UNIQUE INDEX index_job_outbox_on_pending_dedupe ON job_outbox (command_type, dedupe_key) WHERE state = 'pending' AND dedupe_key IS NOT NULL;
  """

  @impl true
  def release, do: "unreleased"

  @impl true
  def data_versions, do: []

  @impl true
  def steps do
    [
      {"20260923180000", &enqueue_ungated_achievements_backfill/1},
      {"20260925100000", &align_track_split_settings_defaults/1},
      {"20260925100100", &reenqueue_transportation_mode_backfills/1, transaction: false},
      {"20260927120000", &create_job_outbox/1},
      {"20261006120000", &add_map_matching_to_tracks/1},
      {"20261006120100", &add_matched_path_index_to_tracks/1, transaction: false}
    ]
  end

  defp enqueue_ungated_achievements_backfill(_repo) do
    {:jobs, [job("DataMigrations::BackfillAchievementsJob")]}
  end

  defp align_track_split_settings_defaults(repo) do
    sql!(repo, ~S"""
    ALTER TABLE "users" ALTER COLUMN "settings" SET DEFAULT '{"fog_of_war_meters":"100","meters_between_routes":"500","minutes_between_routes":"30"}';
    """)
  end

  defp reenqueue_transportation_mode_backfills(repo) do
    tracks_job =
      if select_value(repo, "SELECT EXISTS (SELECT 1 FROM tracks)"),
        do: [job("DataMigrations::BackfillTransportationModesJob")],
        else: []

    import_jobs =
      repo.query!("SELECT id FROM imports WHERE source IN (0, 1, 2, 3, 6) ORDER BY id", [],
        log: false
      ).rows
      |> Enum.with_index(fn [import_id], index ->
        job(
          "TransportationModes::ImportBackfillJob",
          [import_id],
          @import_initial_delay_seconds + index * @import_delay_seconds
        )
      end)

    {:jobs, tracks_job ++ import_jobs}
  end

  def create_job_outbox(repo), do: sql!(repo, @job_outbox_sql)

  defp add_map_matching_to_tracks(repo) do
    sql!(repo, "SET LOCAL lock_timeout = '5s'")

    for {name, type} <- [
          {"matched_path", "geometry(MultiLineString,4326)"},
          {"map_matching_status", "integer"},
          {"map_matching_input_digest", "character varying"},
          {"map_matching_data", "jsonb DEFAULT '{}'::jsonb NOT NULL"},
          {"map_matched_at", "timestamp(6) without time zone"}
        ] do
      add_map_matching_column(repo, name, type, 1)
    end

    :ok
  end

  defp add_map_matching_column(repo, name, type, attempt) do
    unless column?(repo, "tracks", name) do
      repo.query!(~s|ALTER TABLE tracks ADD "#{name}" #{type}|, [],
        mode: :savepoint,
        log: false
      )
    end
  rescue
    error in Postgrex.Error ->
      if error.postgres[:code] == :lock_not_available and attempt < 5 do
        Process.sleep(5 * attempt * 1000)
        add_map_matching_column(repo, name, type, attempt + 1)
      else
        reraise error, __STACKTRACE__
      end
  end

  defp add_matched_path_index_to_tracks(repo) do
    require_zero_lock_timeout!(repo)

    invalid =
      select_value(repo, """
      SELECT NOT i.indisvalid FROM pg_index i
      JOIN pg_class c ON c.oid=i.indexrelid
      WHERE c.oid=to_regclass('index_tracks_on_matched_path')
      """)

    if invalid,
      do: sql!(repo, "DROP INDEX CONCURRENTLY IF EXISTS index_tracks_on_matched_path")

    sql!(repo, """
    CREATE INDEX CONCURRENTLY IF NOT EXISTS index_tracks_on_matched_path
    ON tracks USING gist(matched_path) WHERE matched_path IS NOT NULL
    """)
  end
end

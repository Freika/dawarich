defmodule Dawarich.ReleaseMigrations.V1_0_2 do
  @moduledoc false
  @behaviour Dawarich.ReleaseMigration

  import Dawarich.ReleaseMigration

  @initial_delay_seconds 2 * 60
  @user_delay_seconds 30
  @import_delay_seconds 10

  @index_names_on_columns """
  SELECT i.relname::text
  FROM pg_class t
  JOIN pg_index d ON t.oid = d.indrelid
  JOIN pg_class i ON d.indexrelid = i.oid
  LEFT JOIN pg_namespace n ON n.oid = t.relnamespace
  WHERE i.relkind IN ('i', 'I') AND NOT d.indisprimary AND t.relname = $1
    AND n.nspname = ANY (current_schemas(false))
    AND NOT 0 = ANY (d.indkey::int2[])
    AND ARRAY(SELECT a.attname::text
              FROM unnest(d.indkey::int2[]) WITH ORDINALITY AS k(attnum, ord)
              JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = k.attnum
              WHERE k.ord <= d.indnkeyatts
              ORDER BY k.ord) = $2::text[]
  ORDER BY i.relname
  """

  @impl true
  def release, do: "1.0.2"

  @impl true
  def data_versions, do: []

  @impl true
  def steps do
    [
      {"20260120193124", &add_month_to_digests/1, transaction: false},
      {"20260120193200", &create_track_segments/1},
      {"20260120193336", &add_dominant_mode_to_tracks/1, transaction: false},
      {"20260120193401", &add_travel_patterns_to_digests/1},
      {"20260120193501", &change_tracks_distance_precision/1, transaction: false},
      {"20260124221434", &add_index_to_track_segments/1, transaction: false},
      {"20260125100000", &enqueue_transportation_mode_backfill_jobs/1, transaction: false}
    ]
  end

  defp add_month_to_digests(repo) do
    unless column?(repo, "digests", "month") do
      sql!(repo, ~S|ALTER TABLE "digests" ADD "month" integer;|)
    end

    remove_digests_user_year_period_type_index(repo)

    sql!(
      repo,
      ~S|CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS "index_digests_on_user_year_month_period_type" ON "digests" ("user_id", "year", "month", "period_type");|
    )
  end

  defp create_track_segments(repo) do
    sql!(repo, ~S"""
    CREATE TABLE IF NOT EXISTS "track_segments" ("id" bigserial primary key, "track_id" bigint NOT NULL, "transportation_mode" integer DEFAULT 0 NOT NULL, "start_index" integer NOT NULL, "end_index" integer NOT NULL, "distance" integer, "duration" integer, "avg_speed" float, "max_speed" float, "avg_acceleration" float, "confidence" integer DEFAULT 0, "source" character varying, "created_at" timestamp(6) NOT NULL, "updated_at" timestamp(6) NOT NULL, CONSTRAINT "fk_rails_ef0fcf83b4"
    FOREIGN KEY ("track_id")
      REFERENCES "tracks" ("id")
    );
    CREATE INDEX IF NOT EXISTS "index_track_segments_on_track_id" ON "track_segments" ("track_id");
    CREATE INDEX IF NOT EXISTS "index_track_segments_on_transportation_mode" ON "track_segments" ("transportation_mode");
    CREATE INDEX IF NOT EXISTS "index_track_segments_on_track_id_and_transportation_mode" ON "track_segments" ("track_id", "transportation_mode");
    """)
  end

  defp add_dominant_mode_to_tracks(repo) do
    unless column?(repo, "tracks", "dominant_mode") do
      sql!(repo, ~S|ALTER TABLE "tracks" ADD "dominant_mode" integer DEFAULT 0;|)
    end

    sql!(
      repo,
      ~S|CREATE INDEX CONCURRENTLY IF NOT EXISTS "index_tracks_on_dominant_mode" ON "tracks" ("dominant_mode");|
    )
  end

  defp add_travel_patterns_to_digests(repo) do
    unless column?(repo, "digests", "travel_patterns") do
      sql!(repo, ~S|ALTER TABLE "digests" ADD "travel_patterns" jsonb DEFAULT '{}';|)
    end
  end

  defp change_tracks_distance_precision(repo) do
    sql!(repo, ~S|ALTER TABLE "tracks" ALTER COLUMN "distance" TYPE bigint;|)
  end

  defp add_index_to_track_segments(repo) do
    sql!(
      repo,
      ~S|CREATE INDEX CONCURRENTLY IF NOT EXISTS "index_track_segments_on_track_and_indices" ON "track_segments" ("track_id", "start_index", "end_index");|
    )
  end

  defp enqueue_transportation_mode_backfill_jobs(repo),
    do: {:jobs, user_backfill_jobs(repo) ++ import_backfill_jobs(repo)}

  defp user_backfill_jobs(repo) do
    rescue_sql(
      repo,
      fn ->
        repo
        |> ids("SELECT id FROM users WHERE deleted_at IS NULL")
        |> Enum.with_index(fn user_id, index ->
          job(
            "TransportationModes::BackfillJob",
            [user_id],
            @initial_delay_seconds + index * @user_delay_seconds
          )
        end)
      end,
      :any,
      fn _error -> [] end
    )
  end

  defp import_backfill_jobs(repo) do
    rescue_sql(
      repo,
      fn ->
        repo
        |> ids(
          "SELECT id FROM imports WHERE source IN ('google_semantic_history', 'google_phone_takeout', 'google_records', 'owntracks', 'geojson')"
        )
        |> import_jobs(repo)
      end,
      :any,
      fn _error -> [] end
    )
  end

  defp import_jobs([], _repo), do: []

  defp import_jobs(import_ids, repo) do
    user_count =
      select_value(repo, "SELECT COUNT(*) AS cnt FROM users WHERE deleted_at IS NULL")

    base_delay = @initial_delay_seconds + user_count * @user_delay_seconds

    Enum.with_index(import_ids, fn import_id, index ->
      job(
        "TransportationModes::ImportBackfillJob",
        [import_id],
        base_delay + index * @import_delay_seconds
      )
    end)
  end

  defp ids(repo, sql), do: Enum.map(repo.query!(sql, [], log: false).rows, &hd/1)

  defp remove_digests_user_year_period_type_index(repo) do
    case repo.query!(@index_names_on_columns, ["digests", ~w[user_id year period_type]],
           log: false
         ).rows do
      [] ->
        :ok

      [[name]] ->
        sql!(repo, ~s|DROP INDEX  "#{String.replace(name, ~s("), ~s(""))}";|)

      rows ->
        raise ArgumentError,
              "Multiple indexes found on digests columns [:user_id, :year, :period_type]. " <>
                "Specify an index name from #{rows |> List.flatten() |> Enum.join(", ")}"
    end
  end
end

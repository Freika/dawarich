defmodule Dawarich.ReleaseMigrations.V1_14_1 do
  @moduledoc false
  @behaviour Dawarich.ReleaseMigration

  import Dawarich.ReleaseMigration

  @trips_distance_bigint """
  SELECT 1 FROM pg_attribute
  WHERE attrelid = '"trips"'::regclass AND attname = 'distance' AND attnum > 0 AND NOT attisdropped
    AND format_type(atttypid, atttypmod) IN ('bigint', 'bigint[]')
  """

  @detach_dangling_points """
  UPDATE points SET track_id = NULL WHERE id IN ( SELECT p.id FROM points p LEFT JOIN tracks t ON t.id = p.track_id WHERE p.track_id IS NOT NULL AND t.id IS NULL LIMIT 10000 )
  """

  @impl true
  def release, do: "1.14.1"

  @impl true
  def data_versions, do: []

  @impl true
  def steps do
    [
      {"20260827120000", &add_flight_distance_to_stats_and_digests/1},
      {"20260827200000", &add_points_track_foreign_key/1, transaction: false},
      {"20260827200100", &validate_points_track_foreign_key/1, transaction: false},
      {"20260827210000", &change_trips_distance_to_bigint/1, transaction: false}
    ]
  end

  defp add_flight_distance_to_stats_and_digests(repo) do
    for table <- ~w[stats digests] do
      unless column?(repo, table, "flight_distance") do
        sql!(repo, ~s|ALTER TABLE "#{table}" ADD "flight_distance" bigint DEFAULT 0 NOT NULL;|)
      end
    end
  end

  defp add_points_track_foreign_key(repo) do
    unless points_track_foreign_key(repo) do
      lock_retry!(repo, fn ->
        sql!(repo, ~S"""
        ALTER TABLE "points" ADD CONSTRAINT "fk_rails_67ba69a24d"
        FOREIGN KEY ("track_id")
          REFERENCES "tracks" ("id")
         NOT VALID;
        """)
      end)
    end
  end

  defp validate_points_track_foreign_key(repo) do
    if points_track_foreign_key(repo) do
      repeat_until_zero(repo, @detach_dangling_points)

      name =
        points_track_foreign_key(repo) ||
          raise(ArgumentError, "Table 'points' has no foreign key for tracks")

      sql!(
        repo,
        ~s|ALTER TABLE "points" VALIDATE CONSTRAINT #{quote_ident(name)};|
      )
    end
  end

  defp change_trips_distance_to_bigint(repo) do
    unless exists?(repo, @trips_distance_bigint) do
      lock_retry!(repo, fn ->
        sql!(repo, ~S"""
        ALTER TABLE "trips" ALTER COLUMN "distance" TYPE bigint;
        """)
      end)
    end
  end

  defp points_track_foreign_key(repo),
    do: foreign_key_name(repo, "points", "tracks", "track_id")

  defp lock_retry!(repo, fun),
    do: with_lock_retry!(repo, fun, lock_timeout: "5s", attempts: 5, backoff_seconds: 5)
end

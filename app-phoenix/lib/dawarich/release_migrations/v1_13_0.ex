defmodule Dawarich.ReleaseMigrations.V1_13_0 do
  @moduledoc false
  @behaviour Dawarich.ReleaseMigration

  import Dawarich.ReleaseMigration

  @superseded_points_indexes ~w[
    index_points_on_lonlat_timestamp_user_id
    index_points_on_user_id_and_timestamp
    idx_points_user_country_name
  ]

  @invalid_points_indexes """
  SELECT c.relname
  FROM pg_index i
  JOIN pg_class c ON c.oid = i.indexrelid
  JOIN pg_class t ON t.oid = i.indrelid
  WHERE t.relname = 'points' AND NOT i.indisvalid
    AND c.relname <> 'index_points_on_user_id_timestamp_lonlat'
  """

  @replacement_index_valid """
  SELECT i.indisvalid
  FROM pg_index i
  JOIN pg_class c ON c.oid = i.indexrelid
  JOIN pg_class t ON t.oid = i.indrelid
  WHERE t.relname = 'points' AND c.relname = 'index_points_on_user_id_timestamp_lonlat'
  """

  @replacement_index_unusable """
  index_points_on_user_id_timestamp_lonlat is missing on `points`, or invalid and could not be
  rebuilt automatically.

  Dropping the superseded indexes now would leave `points` with no unique
  index on (user_id, timestamp, lonlat), which every point upsert relies on
  for ON CONFLICT. All ingestion (OwnTracks, Overland, Traccar, imports)
  would fail with "there is no unique or exclusion constraint matching the
  ON CONFLICT specification", and duplicate protection would be lost.

  Repair it first, then re-run this migration:

    DROP INDEX CONCURRENTLY IF EXISTS index_points_on_user_id_timestamp_lonlat;
    CREATE UNIQUE INDEX CONCURRENTLY index_points_on_user_id_timestamp_lonlat
      ON points (user_id, timestamp, lonlat);
  """

  @impl true
  def release, do: "1.13.0"

  @impl true
  def data_versions, do: []

  @impl true
  def steps do
    [{"20260816120000", &drop_superseded_points_indexes/1, transaction: false}]
  end

  defp drop_superseded_points_indexes(repo) do
    require_zero_lock_timeout!(repo)
    drop_invalid_indexes_on_points(repo)
    ensure_replacement_index_usable!(repo)

    for name <- @superseded_points_indexes,
        do: remove_index_concurrently_if_exists(repo, "points", name)
  end

  defp drop_invalid_indexes_on_points(repo) do
    for [name] <- repo.query!(@invalid_points_indexes, [], log: false).rows do
      sql!(repo, "DROP INDEX CONCURRENTLY IF EXISTS #{quote_ident(name)};")
    end
  end

  defp ensure_replacement_index_usable!(repo) do
    usable =
      case replacement_index_valid(repo) do
        false ->
          repair_replacement_index(repo)
          replacement_index_valid(repo)

        usable ->
          usable
      end

    unless usable, do: raise(@replacement_index_unusable)
  end

  defp replacement_index_valid(repo), do: select_value(repo, @replacement_index_valid)

  defp repair_replacement_index(repo) do
    rescue_sql(
      repo,
      fn ->
        sql!(repo, ~S"""
        REINDEX INDEX CONCURRENTLY "index_points_on_user_id_timestamp_lonlat";
        """)
      end,
      :any,
      fn _error -> :ok end
    )
  end
end

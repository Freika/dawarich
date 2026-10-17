defmodule Dawarich.ReleaseMigrations.V1_11_0 do
  @moduledoc false
  @behaviour Dawarich.ReleaseMigration

  import Dawarich.ReleaseMigration

  @visits_unique "idx_visits_user_started_at_place_unique"
  @track_segments_unique "idx_track_segments_track_start_index_unique"
  @places_external "idx_places_user_external_place_id"

  @invalid_index """
  SELECT 1 FROM pg_class c JOIN pg_index i ON i.indexrelid = c.oid
  WHERE c.relname = $1 AND i.indisvalid = false
  """

  @unsupported_import_ids """
  SELECT id FROM imports
  WHERE additional_data_extraction_status = 0 AND (source IS NULL OR source NOT IN (0, 3, 13))
    AND ($1::bigint IS NULL OR id > $1)
  ORDER BY id LIMIT 5000
  """

  @mark_imports_unsupported """
  UPDATE imports SET additional_data_extraction_status = 5
  WHERE additional_data_extraction_status = 0 AND (source IS NULL OR source NOT IN (0, 3, 13))
    AND id = ANY($1)
  """

  @impl true
  def release, do: "1.11.0"

  @impl true
  def data_versions, do: []

  @impl true
  def steps do
    [
      {"20260730160000", &enqueue_google_records_device_tag_backfill/1},
      {"20260730200000", &enable_poster_ordering_flag/1},
      {"20260730210000", &add_extraction_columns_to_imports/1, transaction: false},
      {"20260730210100", &backfill_unsupported_extraction_status/1, transaction: false},
      {"20260730210150", &dedupe_visits_before_unique_index/1, transaction: false},
      {"20260730210200", &add_unique_index_to_visits/1, transaction: false},
      {"20260730210250", &dedupe_track_segments_before_unique_index/1, transaction: false},
      {"20260730210300", &add_unique_index_to_track_segments/1, transaction: false},
      {"20260730210400", &add_external_place_id_index_to_places/1, transaction: false},
      {"20260730220000", &add_import_id_to_extraction_artifacts/1, transaction: false},
      {"20260802120000", &enqueue_anomaly_recalculation/1}
    ]
  end

  defp enqueue_google_records_device_tag_backfill(_repo),
    do: {:jobs, [job("DataMigrations::RecalculatePerTrackerTracksJob")]}

  defp enable_poster_ordering_flag(repo) do
    sql!(repo, ~S"""
    INSERT INTO flipper_features (key, created_at, updated_at) SELECT 'poster_ordering', now(), now() WHERE NOT EXISTS (SELECT 1 FROM flipper_features WHERE key = 'poster_ordering');
    DELETE FROM flipper_gates WHERE feature_key = 'poster_ordering';
    INSERT INTO flipper_gates (feature_key, key, value, created_at, updated_at) VALUES ('poster_ordering', 'boolean', 'true', now(), now());
    """)
  end

  defp add_extraction_columns_to_imports(repo) do
    unless column?(repo, "imports", "additional_data_extraction_status") do
      sql!(repo, ~S"""
      ALTER TABLE "imports" ADD "additional_data_extraction_status" integer DEFAULT 0 NOT NULL;
      """)
    end

    unless column?(repo, "imports", "additional_data_extraction") do
      sql!(repo, ~S"""
      ALTER TABLE "imports" ADD "additional_data_extraction" jsonb DEFAULT '{}' NOT NULL;
      """)
    end

    unless index_name?(repo, "imports", "index_imports_on_additional_data_extraction_status") do
      sql!(repo, ~S"""
      CREATE INDEX CONCURRENTLY "index_imports_on_additional_data_extraction_status" ON "imports" ("additional_data_extraction_status");
      """)
    end
  end

  defp backfill_unsupported_extraction_status(repo), do: mark_imports_unsupported(repo, nil)

  defp mark_imports_unsupported(repo, after_id) do
    ids = List.flatten(repo.query!(@unsupported_import_ids, [after_id], log: false).rows)

    if ids != [] do
      repo.query!(@mark_imports_unsupported, [ids], log: false)
      if length(ids) == 5000, do: mark_imports_unsupported(repo, List.last(ids))
    end
  end

  defp dedupe_visits_before_unique_index(repo) do
    sql!(repo, "DROP TABLE IF EXISTS visit_dedupe_plan;")

    sql!(repo, ~S"""
    CREATE UNLOGGED TABLE visit_dedupe_plan AS SELECT min(id) AS keeper, array_agg(id) AS ids FROM visits WHERE place_id IS NOT NULL GROUP BY user_id, started_at, place_id HAVING count(*) > 1;
    """)

    collapse_planned_visit_groups(repo)
  after
    sql!(repo, "DROP TABLE IF EXISTS visit_dedupe_plan;")
  end

  defp collapse_planned_visit_groups(repo) do
    case repo.query!("SELECT keeper, ids FROM visit_dedupe_plan LIMIT 500", [], log: false).rows do
      [] ->
        :ok

      rows ->
        Enum.each(rows, fn [keeper, ids] ->
          losers = Enum.reject(ids, &(&1 == keeper))
          if losers != [], do: collapse_visits(repo, keeper, losers)
        end)

        repo.query!(
          "DELETE FROM visit_dedupe_plan WHERE keeper = ANY($1)",
          [Enum.map(rows, &hd/1)],
          log: false
        )

        collapse_planned_visit_groups(repo)
    end
  end

  defp collapse_visits(repo, keeper, losers) do
    repo.transaction(fn ->
      repo.query!("UPDATE points SET visit_id = $1 WHERE visit_id = ANY($2)", [keeper, losers],
        log: false
      )

      if table?(repo, "place_visits"),
        do: repo.query!("DELETE FROM place_visits WHERE visit_id = ANY($1)", [losers], log: false)

      repo.query!("DELETE FROM visits WHERE id = ANY($1)", [losers], log: false)
    end)
  end

  defp add_unique_index_to_visits(repo) do
    add_unique_index(
      repo,
      "visits",
      @visits_unique,
      ~S"""
      CREATE UNIQUE INDEX CONCURRENTLY "idx_visits_user_started_at_place_unique" ON "visits" ("user_id", "started_at", "place_id");
      """,
      &collapse_visit_stragglers/1
    )
  end

  defp collapse_visit_stragglers(repo) do
    sql!(repo, "DROP TABLE IF EXISTS visit_straggler_losers;")

    sql!(repo, ~S"""
    CREATE UNLOGGED TABLE visit_straggler_losers AS SELECT v.id, g.keeper FROM visits v JOIN ( SELECT user_id, started_at, place_id, min(id) AS keeper FROM visits WHERE place_id IS NOT NULL GROUP BY user_id, started_at, place_id HAVING count(*) > 1 ) g ON v.user_id = g.user_id AND v.started_at = g.started_at AND v.place_id = g.place_id WHERE v.id <> g.keeper;
    """)

    sql!(repo, ~S"""
    UPDATE points SET visit_id = visit_straggler_losers.keeper FROM visit_straggler_losers WHERE points.visit_id = visit_straggler_losers.id;
    """)

    if table?(repo, "place_visits") do
      sql!(repo, ~S"""
      DELETE FROM place_visits WHERE visit_id IN (SELECT id FROM visit_straggler_losers);
      """)
    end

    sql!(repo, "DELETE FROM visits WHERE id IN (SELECT id FROM visit_straggler_losers);")
  after
    sql!(repo, "DROP TABLE IF EXISTS visit_straggler_losers;")
  end

  defp dedupe_track_segments_before_unique_index(repo) do
    sql!(repo, "DROP TABLE IF EXISTS track_segment_dedupe_plan;")

    sql!(repo, ~S"""
    CREATE UNLOGGED TABLE track_segment_dedupe_plan AS SELECT id FROM ( SELECT id, row_number() OVER (PARTITION BY track_id, start_index ORDER BY id) AS position FROM track_segments ) ranked WHERE ranked.position > 1;
    """)

    delete_planned_track_segments(repo)
  after
    sql!(repo, "DROP TABLE IF EXISTS track_segment_dedupe_plan;")
  end

  defp delete_planned_track_segments(repo) do
    sql = "SELECT id FROM track_segment_dedupe_plan LIMIT 500"

    case List.flatten(repo.query!(sql, [], log: false).rows) do
      [] ->
        :ok

      ids ->
        repo.query!("DELETE FROM track_segments WHERE id = ANY($1)", [ids], log: false)
        repo.query!("DELETE FROM track_segment_dedupe_plan WHERE id = ANY($1)", [ids], log: false)
        delete_planned_track_segments(repo)
    end
  end

  defp add_unique_index_to_track_segments(repo) do
    add_unique_index(
      repo,
      "track_segments",
      @track_segments_unique,
      ~S"""
      CREATE UNIQUE INDEX CONCURRENTLY "idx_track_segments_track_start_index_unique" ON "track_segments" ("track_id", "start_index");
      """,
      &delete_duplicate_track_segments/1
    )
  end

  defp delete_duplicate_track_segments(repo) do
    sql!(repo, ~S"""
    DELETE FROM track_segments WHERE id IN ( SELECT id FROM ( SELECT id, row_number() OVER (PARTITION BY track_id, start_index ORDER BY id) AS position FROM track_segments ) ranked WHERE ranked.position > 1 );
    """)
  end

  defp add_external_place_id_index_to_places(repo) do
    drop_invalid_index(repo, @places_external)

    unless index_name?(repo, "places", @places_external) do
      sql!(repo, ~S"""
      CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS idx_places_user_external_place_id ON places (user_id, ((geodata ->> 'external_place_id'))) WHERE (geodata ->> 'external_place_id') IS NOT NULL;
      """)
    end
  end

  defp add_import_id_to_extraction_artifacts(repo) do
    for table <- ~w[visits places tracks] do
      unless column?(repo, table, "import_id"),
        do: sql!(repo, ~s|ALTER TABLE "#{table}" ADD "import_id" bigint;|)

      index = "idx_#{table}_import_id_extracted"

      unless index_name?(repo, table, index) do
        sql!(
          repo,
          ~s|CREATE INDEX CONCURRENTLY "#{index}" ON "#{table}" ("import_id") WHERE import_id IS NOT NULL;|
        )
      end
    end
  end

  defp enqueue_anomaly_recalculation(_repo),
    do: {:jobs, [job("DataMigrations::RecalculateAnomaliesJob")]}

  defp add_unique_index(repo, table, name, create_index, repair) do
    rescue_sql(
      repo,
      fn ->
        drop_invalid_index(repo, name)
        unless index_name?(repo, table, name), do: sql!(repo, create_index)
      end,
      [:unique_violation],
      fn _error ->
        drop_invalid_index(repo, name)
        repair.(repo)
        sql!(repo, create_index)
      end
    )
  end

  defp drop_invalid_index(repo, name) do
    if exists?(repo, @invalid_index, [name]),
      do: sql!(repo, ~s|DROP INDEX CONCURRENTLY "#{name}";|)
  end
end

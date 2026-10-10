defmodule Dawarich.Jobs.ControlTablesTest do
  use Dawarich.JobsCase, async: true, group: :scratch_db

  @sql_file Path.expand("../../../priv/repo/sql/20260927120100_job_control.sql", __DIR__)
  @sha256 "400326b0bf4b2bd9712f38628e8351b641ceb4b042c9d320f018a3496a036694"
  @rails_commands_sql Path.expand(
                        "../../../priv/repo/sql/20260928130000_rails_commands.sql",
                        __DIR__
                      )
  @rails_commands_sha256 "7efd39608949f81eb3d750262a3df4365b7406d0caa622923008759381a0a571"
  @track_generations_sql Path.expand(
                           "../../../priv/repo/sql/20260928150000_track_generations.sql",
                           __DIR__
                         )
  @track_generations_sha256 "c22d472f6e342d7746693f55b401be8e1e068b1e34760e0879c01f31d06be090"

  test "the migration creates the six phoenix tables" do
    for table <-
          ~w(job_owners job_outbox_replays processed_commands runtime_nodes app_version trip_events) do
      assert [[true]] == rows("SELECT to_regclass($1) IS NOT NULL", ["phoenix." <> table])
    end
  end

  test "the shared SQL file is frozen; a change needs a new migration and a new file" do
    assert :crypto.hash(:sha256, File.read!(@sql_file)) |> Base.encode16(case: :lower) == @sha256
  end

  test "the reverse-outbox migration creates phoenix.rails_commands and rails_commands_dead" do
    assert columns("rails_commands") == [
             ["id", "bigint", "NO"],
             ["kind", "text", "NO"],
             ["payload", "jsonb", "NO"],
             ["attempts", "integer", "NO"],
             ["available_at", "timestamp with time zone", "NO"],
             ["leased_until", "timestamp with time zone", "YES"],
             ["created_at", "timestamp with time zone", "NO"]
           ]

    assert columns("rails_commands_dead") == [
             ["id", "bigint", "NO"],
             ["kind", "text", "NO"],
             ["payload", "jsonb", "NO"],
             ["attempts", "integer", "NO"],
             ["last_error", "text", "NO"],
             ["created_at", "timestamp with time zone", "NO"],
             ["died_at", "timestamp with time zone", "NO"]
           ]
  end

  test "a Phoenix-inserted command is due at once, unleased, with zero attempts" do
    assert rows("""
           INSERT INTO phoenix.rails_commands (kind) VALUES ('k')
           RETURNING attempts, available_at <= now(), leased_until IS NULL
           """) == [[0, true, true]]
  end

  test "the rails_commands SQL file is frozen" do
    assert :crypto.hash(:sha256, File.read!(@rails_commands_sql)) |> Base.encode16(case: :lower) ==
             @rails_commands_sha256
  end

  test "owners are sidekiq or oban and app_version holds one row" do
    assert_raise Postgrex.Error, ~r/job_owners_owner_check/, fn ->
      rows("INSERT INTO phoenix.job_owners (key, owner) VALUES ('k', 'redis')")
    end

    rows("INSERT INTO phoenix.app_version (latest_version, checked_at) VALUES ('1.0.0', now())")

    assert_raise Postgrex.Error, ~r/app_version_pkey|app_version_id_check/, fn ->
      rows("INSERT INTO phoenix.app_version (latest_version, checked_at) VALUES ('1.0.1', now())")
    end
  end

  test "oban_jobs is vacuumed at 2 % churn" do
    assert [[options]] =
             rows("SELECT reloptions FROM pg_class WHERE oid = 'oban.oban_jobs'::regclass")

    assert "autovacuum_vacuum_scale_factor=0.02" in options
    assert "autovacuum_analyze_scale_factor=0.02" in options
  end

  test "the scratch database runs in a non-UTC server zone while the connection sees UTC" do
    assert [["UTC"]] == rows("SHOW TimeZone")

    assert [["TimeZone=Pacific/Chatham"]] ==
             rows("""
             SELECT unnest(setconfig) FROM pg_db_role_setting
             WHERE setdatabase = (SELECT oid FROM pg_database WHERE datname = current_database())
             """)
  end

  test "the wave-5 migration creates both generation tables" do
    assert columns("track_generations") == [
             ["id", "uuid", "NO"],
             ["user_id", "bigint", "NO"],
             ["mode", "text", "NO"],
             ["untracked_only", "boolean", "NO"],
             ["import_id", "bigint", "YES"],
             ["low_priority", "boolean", "NO"],
             ["status", "text", "NO"],
             ["total_chunks", "integer", "NO"],
             ["completed_chunks", "integer", "NO"],
             ["tracks_created", "integer", "NO"],
             ["poll_count", "integer", "NO"],
             ["stall_count", "integer", "NO"],
             ["seen_completed", "integer", "NO"],
             ["error", "text", "YES"],
             ["created_at", "timestamp with time zone", "NO"],
             ["updated_at", "timestamp with time zone", "NO"]
           ]

    assert columns("track_generation_chunks") == [
             ["generation_id", "uuid", "NO"],
             ["chunk_id", "integer", "NO"],
             ["start_ts", "bigint", "NO"],
             ["end_ts", "bigint", "NO"],
             ["buffer_start_ts", "bigint", "NO"],
             ["buffer_end_ts", "bigint", "NO"],
             ["status", "text", "NO"],
             ["tracks_created", "integer", "NO"]
           ]

    assert [["c"]] =
             rows("""
             SELECT confdeltype::text FROM pg_constraint
             WHERE conrelid = 'phoenix.track_generation_chunks'::regclass AND contype = 'f'
             """)
  end

  test "status checks reject unknown states" do
    rows("""
    INSERT INTO phoenix.track_generations (id, user_id, mode, untracked_only, low_priority, status, total_chunks)
    VALUES (gen_random_uuid(), 1, 'bulk', false, false, 'running', 1)
    """)

    assert_raise Postgrex.Error, ~r/track_generations_status_check/, fn ->
      rows("""
      INSERT INTO phoenix.track_generations (id, user_id, mode, untracked_only, low_priority, status, total_chunks)
      VALUES (gen_random_uuid(), 1, 'bulk', false, false, 'queued', 1)
      """)
    end

    assert_raise Postgrex.Error, ~r/track_generations_total_chunks_check/, fn ->
      rows("""
      INSERT INTO phoenix.track_generations (id, user_id, mode, untracked_only, low_priority, status, total_chunks)
      VALUES (gen_random_uuid(), 1, 'bulk', false, false, 'running', 0)
      """)
    end
  end

  test "the track-generations SQL file is frozen" do
    assert :crypto.hash(:sha256, File.read!(@track_generations_sql))
           |> Base.encode16(case: :lower) ==
             @track_generations_sha256
  end

  defp columns(table) do
    rows(
      """
      SELECT column_name, data_type, is_nullable FROM information_schema.columns
      WHERE table_schema = 'phoenix' AND table_name = $1 ORDER BY ordinal_position
      """,
      [table]
    )
  end
end

defmodule Dawarich.Jobs.ControlTablesTest do
  use Dawarich.JobsCase

  @sql_file Path.expand("../../../priv/repo/sql/20260927120100_job_control.sql", __DIR__)
  @sha256 "400326b0bf4b2bd9712f38628e8351b641ceb4b042c9d320f018a3496a036694"

  test "the migration creates the six phoenix tables" do
    for table <-
          ~w(job_owners job_outbox_replays processed_commands runtime_nodes app_version trip_events) do
      assert [[true]] == rows("SELECT to_regclass($1) IS NOT NULL", ["phoenix." <> table])
    end
  end

  test "the shared SQL file is frozen; a change needs a new migration and a new file" do
    assert :crypto.hash(:sha256, File.read!(@sql_file)) |> Base.encode16(case: :lower) == @sha256
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
end

defmodule Dawarich.ReleaseOperations.AddPointDimensionsTest do
  use Dawarich.ScratchCase

  alias Dawarich.ReleaseMigration
  alias Dawarich.ReleaseOperations.{AddPointDimensions, PointBackfill}

  import ExUnit.CaptureLog

  setup do
    Dawarich.FixtureCleanup.delete!(ScratchRepo, ~w(oban.oban_jobs))
    scratch_sql!("CREATE TABLE points (id bigserial PRIMARY KEY)")
    previous = Map.take(System.get_env(), ["SELF_HOSTED", "SKIP_POINT_DIMENSION_BACKFILL"])
    System.put_env("SELF_HOSTED", "true")
    System.delete_env("SKIP_POINT_DIMENSION_BACKFILL")

    on_exit(fn ->
      System.delete_env("SELF_HOSTED")
      System.delete_env("SKIP_POINT_DIMENSION_BACKFILL")
      System.put_env(previous)
      scratch_sql!("ALTER TABLE oban.oban_jobs DROP CONSTRAINT IF EXISTS a12h_child_failure")
    end)

    :ok
  end

  @tag a12f3b_case: "E17a"
  test "adds source_id and starts dimensions only when the source gate permits" do
    changeset = AddPointDimensions.new(%{"version" => 1})
    assert changeset.valid?
    assert Ecto.Changeset.get_field(changeset, :max_attempts) == 288
    assert AddPointDimensions.backoff(%Oban.Job{attempt: 2}) == 300
    log = capture_log(fn -> AddPointDimensions.log_exhaustion(nil) end)
    assert log =~ "ALTER TABLE points ADD COLUMN IF NOT EXISTS source_id integer"
    assert log =~ "BackfillPointDimensionsJob.perform_later"

    assert AddPointDimensions.run(ScratchRepo) == :ok
    assert ReleaseMigration.column?(ScratchRepo, "points", "source_id")
    assert [[args, "maintenance", 3, 10]] = children()
    assert args["version"] == 1
    assert {:ok, _} = Ecto.UUID.cast(args["operation_id"])

    assert args["cursor"] == %{
             "phase" => "dimensions",
             "start_id" => nil,
             "batch_size" => 50_000,
             "repair_collisions" => false
           }

    assert ScratchRepo.query!(
             "SELECT count(*) FROM oban.oban_jobs WHERE state NOT IN ('completed','cancelled')",
             [],
             log: false
           ).rows == [[1]]

    assert ScratchRepo.query!("SELECT count(*) FROM phoenix.rails_commands", [], log: false).rows ==
             [[0]]

    Dawarich.FixtureCleanup.delete!(ScratchRepo, ~w(oban.oban_jobs))
    assert AddPointDimensions.run(ScratchRepo) == :ok
    assert length(children()) == 1

    for {name, value} <- [{"SELF_HOSTED", "false"}, {"SKIP_POINT_DIMENSION_BACKFILL", "1"}] do
      Dawarich.FixtureCleanup.delete!(ScratchRepo, ~w(oban.oban_jobs))
      scratch_sql!("ALTER TABLE points DROP COLUMN source_id")
      System.put_env("SELF_HOSTED", "true")
      System.put_env(name, value)
      assert AddPointDimensions.run(ScratchRepo) == :ok
      assert ReleaseMigration.column?(ScratchRepo, "points", "source_id")
      assert children() == []
    end
  end

  @tag a12f3b_case: "E17b"
  test "child enqueue failure leaves committed source_id and no child" do
    parent =
      ScratchRepo.insert!(AddPointDimensions.new(%{"version" => 1}), prefix: "oban", log: false)

    scratch_sql!("""
    ALTER TABLE oban.oban_jobs ADD CONSTRAINT a12h_child_failure
    CHECK (worker <> 'Elixir.Dawarich.ReleaseOperations.PointBackfill'
      AND worker <> 'Dawarich.ReleaseOperations.PointBackfill')
    """)

    error =
      assert_raise Ecto.ConstraintError, fn -> AddPointDimensions.run(ScratchRepo, parent) end

    assert error.message =~ "a12h_child_failure"
    assert ReleaseMigration.column?(ScratchRepo, "points", "source_id")
    assert children() == []

    assert ScratchRepo.query!("SELECT state FROM oban.oban_jobs WHERE id=$1", [parent.id],
             log: false
           ).rows == [["available"]]
  end

  test "failed add commits neither DDL nor child" do
    scratch_sql!("ALTER TABLE points RENAME TO source_points")
    scratch_sql!("CREATE VIEW points AS SELECT * FROM source_points")
    error = assert_raise Postgrex.Error, fn -> AddPointDimensions.run(ScratchRepo) end
    assert error.postgres.code == :wrong_object_type
    refute ReleaseMigration.column?(ScratchRepo, "source_points", "source_id")
    assert children() == []
  end

  defp children do
    ScratchRepo.query!(
      "SELECT args,queue,priority,max_attempts FROM oban.oban_jobs WHERE worker=$1",
      [Oban.Worker.to_string(PointBackfill)],
      log: false
    ).rows
  end
end

defmodule Dawarich.Imports.InterruptedFailureTest do
  use Dawarich.JobsCase
  alias Dawarich.A12f3bImportsFixture, as: F
  alias Dawarich.Imports.{ProcessWorker, ProcessGpxWorker, NormalHandover}
  alias Dawarich.Jobs.{Ownership, Processed, Registry}

  setup do: F.setup()

  defp normal(c, source \\ nil) do
    rows("UPDATE imports SET source=$2 WHERE id=$1", [c.import.id, source])

    rows("UPDATE oban.oban_jobs SET worker='Dawarich.Imports.ProcessWorker' WHERE id=$1", [
      c.job.id
    ])

    Ownership.put!(ScratchRepo, "command:imports.process_normal", :oban)
    %{c | job: %{c.job | worker: "Dawarich.Imports.ProcessWorker"}}
  end

  defp install_interrupt do
    rows("""
    CREATE FUNCTION public.review_advance_attempt() RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN
      UPDATE oban.oban_jobs SET attempt=2 WHERE state='executing' AND attempt=1;
      RETURN NEW;
    END; $$
    """)

    rows(
      "CREATE TRIGGER review_advance_attempt AFTER INSERT ON notifications FOR EACH ROW EXECUTE FUNCTION public.review_advance_attempt()"
    )
  end

  defp remove_interrupt do
    rows("DROP TRIGGER review_advance_attempt ON notifications")
    rows("DROP FUNCTION public.review_advance_attempt()")
  end

  for mode <- ["on", "off"] do
    @mode mode
    test "normal-discovered GPX notification is exactly once after interrupted failure in #{@mode}",
         base do
      c = normal(base)
      F.blob(c, "broken.gpx", "<gpx><trk>", "file")
      System.put_env("DAWARICH_RAILS", @mode)
      install_interrupt()

      try do
        assert ProcessWorker.perform(c.job) in [{:snooze, 5}, {:cancel, "stale import attempt"}]
      after
        remove_interrupt()
      end

      assert [[4, status]] = rows("SELECT source,status FROM imports WHERE id=$1", [c.import.id])
      assert status in [1, 3]

      assert [["processing", 1]] =
               rows("SELECT phase,attempt FROM phoenix.import_runs WHERE import_id=$1", [
                 c.import.id
               ])

      assert [[count]] =
               rows("SELECT count(*) FROM notifications WHERE user_id=$1", [c.import.user_id])

      assert count in [0, 1]

      rows("UPDATE oban.oban_jobs SET attempt=2 WHERE id=$1", [c.job.id])
      assert :ok = ProcessWorker.perform(%{c.job | attempt: 2})
      assert Processed.done?(ScratchRepo, c.job.args["event_id"])

      assert [[1]] ==
               rows("SELECT count(*) FROM notifications WHERE user_id=$1", [c.import.user_id])
    end
  end

  for mode <- ["on", "off"] do
    test "queued normal job edited to GPX has a terminal executor in #{mode}", base do
      c = normal(base)
      System.put_env("DAWARICH_RAILS", unquote(mode))
      for entry <- Registry.entries(), do: Ownership.put!(ScratchRepo, entry.key, :oban)

      assert {:ok, :updated} =
               Dawarich.Imports.UiRecords.update(ScratchRepo, c.import.user_id, c.import.id, %{
                 "source" => "gpx"
               })

      F.blob(
        c,
        "route.gpx",
        "<gpx><trk><trkseg><trkpt lat='52.5' lon='13.4'><time>2026-01-15T12:00:00Z</time></trkpt></trkseg></trk></gpx>",
        "file"
      )

      assert :ok = ProcessWorker.perform(c.job)

      assert [[2]] == rows("SELECT status FROM imports WHERE id=$1", [c.import.id])
      assert [[1]] == rows("SELECT count(*) FROM points WHERE import_id=$1", [c.import.id])
      assert [] == rows("SELECT kind FROM phoenix.rails_commands")
      assert [] == rows("SELECT event_id FROM phoenix.import_handoffs")

      assert Processed.done?(ScratchRepo, c.job.args["event_id"])

      for attempt <- 2..3 do
        rows("UPDATE oban.oban_jobs SET attempt=$2 WHERE id=$1", [c.job.id, attempt])
        assert :ok = ProcessWorker.perform(%{c.job | attempt: attempt})
      end

      assert [[0]] ==
               rows("SELECT count(*) FROM notifications WHERE user_id=$1", [c.import.user_id])

      assert [[1]] ==
               rows("SELECT count(*) FROM points WHERE import_id=$1", [c.import.id])

      assert [[0]] ==
               rows(
                 "SELECT count(*) FROM phoenix.rails_commands WHERE kind='imports.normal_resume'"
               )
    end
  end

  for mode <- ["on", "off"] do
    @mode mode
    test "dedicated GPX failure atomically retains one notification in #{@mode}", c do
      F.blob(c, "broken.gpx", "<gpx><trk>", "file")
      System.put_env("DAWARICH_RAILS", @mode)
      install_interrupt()

      try do
        assert {:snooze, 5} = ProcessGpxWorker.perform(c.job)
      after
        remove_interrupt()
      end

      assert [[0]] =
               rows("SELECT count(*) FROM notifications WHERE user_id=$1", [c.import.user_id])

      assert [[1]] = rows("SELECT attempt FROM oban.oban_jobs WHERE id=$1", [c.job.id])
      rows("UPDATE oban.oban_jobs SET attempt=2 WHERE id=$1", [c.job.id])
      assert :ok = ProcessGpxWorker.perform(%{c.job | attempt: 2})

      assert [[1]] =
               rows("SELECT count(*) FROM notifications WHERE user_id=$1", [c.import.user_id])
    end
  end

  test "older receipt never authorizes old executing attempt or another job", base do
    c = normal(base, nil)

    F.blob(
      c,
      "route.gpx",
      "<gpx><trk><trkseg><trkpt lat='52.5' lon='13.4'><time>2026-01-15T12:00:00Z</time></trkpt></trkseg></trk></gpx>",
      "file"
    )

    assert :ok = ProcessWorker.perform(c.job)

    rows("DELETE FROM phoenix.processed_commands WHERE event_id=$1", [
      Ecto.UUID.dump!(c.job.args["event_id"])
    ])

    rows("UPDATE oban.oban_jobs SET attempt=2 WHERE id=$1", [c.job.id])
    assert NormalHandover.owns_source?(ScratchRepo, %{c.job | attempt: 2}, 4)
    refute NormalHandover.owns_source?(ScratchRepo, %{c.job | id: c.job.id + 1000, attempt: 2}, 4)

    refute NormalHandover.owns_source?(
             ScratchRepo,
             %{c.job | args: Map.put(c.job.args, "event_id", Ecto.UUID.generate()), attempt: 2},
             4
           )

    assert {:cancel, "stale import attempt"} = ProcessWorker.perform(c.job)
    assert :ok = ProcessWorker.perform(%{c.job | attempt: 2})
    assert [[1]] = rows("SELECT count(*) FROM points WHERE import_id=$1", [c.import.id])
  end
end

defmodule Dawarich.Imports.InterruptedEmptySuccessTest do
  use Dawarich.JobsCase
  alias Dawarich.A12f3bImportsFixture, as: F
  alias Dawarich.Imports.ProcessWorker
  alias Dawarich.Jobs.{Ownership, Processed}
  setup do: F.setup()

  for {name, bytes} <- [
        {"empty.gpx", "<gpx><trk><trkseg/></trk></gpx>"},
        {"empty.kml", "<kml><Document/></kml>"}
      ],
      mode <- ["on", "off"] do
    @tag empty_success: "#{name}-#{mode}"
    test "empty #{name} notification exactly once across interrupted success in #{mode}", c do
      System.put_env("DAWARICH_RAILS", unquote(mode))
      rows("UPDATE imports SET source=NULL WHERE id=$1", [c.import.id])

      rows("UPDATE oban.oban_jobs SET worker='Dawarich.Imports.ProcessWorker' WHERE id=$1", [
        c.job.id
      ])

      Ownership.put!(ScratchRepo, "command:imports.process_normal", :oban)
      job = %{c.job | worker: "Dawarich.Imports.ProcessWorker"}
      F.blob(c, unquote(name), unquote(bytes), "file")

      rows("""
      CREATE FUNCTION public.empty_success_advance_attempt() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        UPDATE oban.oban_jobs SET attempt=2 WHERE id=#{c.job.id} AND state='executing' AND attempt=1;
        RETURN NEW;
      END; $$
      """)

      rows(
        "CREATE TRIGGER empty_success_advance_attempt AFTER INSERT ON notifications FOR EACH ROW EXECUTE FUNCTION public.empty_success_advance_attempt()"
      )

      try do
        result = ProcessWorker.perform(job)
        assert result in [{:snooze, 5}, {:cancel, "stale import attempt"}]
      after
        rows("DROP TRIGGER empty_success_advance_attempt ON notifications")
        rows("DROP FUNCTION public.empty_success_advance_attempt()")
      end

      assert [[1]] == rows("SELECT status FROM imports WHERE id=$1", [c.import.id])

      assert [["processing", 1]] ==
               rows("SELECT phase,attempt FROM phoenix.import_runs WHERE import_id=$1", [
                 c.import.id
               ])

      rows("UPDATE oban.oban_jobs SET attempt=2 WHERE id=$1", [job.id])
      assert :ok = ProcessWorker.perform(%{job | attempt: 2})

      assert [["terminal", 2]] ==
               rows("SELECT phase,attempt FROM phoenix.import_runs WHERE import_id=$1", [
                 c.import.id
               ])

      assert [[0]] == rows("SELECT count(*) FROM points WHERE import_id=$1", [c.import.id])
      assert Processed.done?(ScratchRepo, job.args["event_id"])
      assert [[2]] == rows("SELECT status FROM imports WHERE id=$1", [c.import.id])

      assert [[1, "Import completed with no points"]] ==
               rows("SELECT kind,title FROM notifications WHERE user_id=$1", [c.import.user_id])

      assert :ok = ProcessWorker.perform(%{job | attempt: 2})

      assert [[1]] ==
               rows("SELECT count(*) FROM notifications WHERE user_id=$1", [c.import.user_id])
    end
  end
end

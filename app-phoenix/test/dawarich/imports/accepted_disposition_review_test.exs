defmodule Dawarich.Imports.AcceptedDispositionReviewTest do
  use Dawarich.JobsCase
  alias Dawarich.A12f3bImportsFixture, as: F
  alias Dawarich.Imports.{Events, ProcessWorker, ProcessGpxWorker}
  alias Dawarich.Jobs.{Ownership, Processed, Registry}
  setup do: F.setup()

  @tag review_case: "mixed-gpx"
  test "edited GPX normal execution has one native progress transport with mixed owners", c do
    own_all()
    System.put_env("DAWARICH_RAILS", "on")
    Ownership.put!(ScratchRepo, "command:imports.process_gpx", :sidekiq, pinned: true)
    c = normal(c)
    rows("UPDATE imports SET source=10 WHERE id=$1", [c.import.id])

    assert {:ok, :updated} ==
             Dawarich.Imports.UiRecords.update(ScratchRepo, c.import.user_id, c.import.id, %{
               "source" => "gpx"
             })

    F.blob(
      c,
      "route.gpx",
      "<gpx><trk><trkseg><trkpt lat='52.5' lon='13.4'><time>2026-01-15T12:00:00Z</time></trkpt></trkseg></trk></gpx>",
      "file"
    )

    Events.subscribe(c.import.user_id)
    assert :ok == ProcessWorker.perform(c.job)
    assert [[2]] == rows("SELECT status FROM imports WHERE id=$1", [c.import.id])
    assert [[1]] == rows("SELECT count(*) FROM points WHERE import_id=$1", [c.import.id])
    assert_receive :imports_changed
    assert [] == rows("SELECT kind FROM phoenix.rails_commands WHERE kind='imports.progress'")
  end

  for mode <- ["on", "off"] do
    @tag review_case: "terminal-#{mode}"
    test "native accepted failure sends terminal import progress in #{mode}", c do
      own_all()
      System.put_env("DAWARICH_RAILS", unquote(mode))
      rows("UPDATE imports SET source=6 WHERE id=$1", [c.import.id])
      Events.subscribe(c.import.user_id)
      reject_settlement(c)
      Ownership.put!(ScratchRepo, "command:imports.process_normal", :sidekiq, pinned: true)
      assert :ok == ProcessGpxWorker.perform(c.job)
      assert [[3]] == rows("SELECT status FROM imports WHERE id=$1", [c.import.id])

      assert [[1]] ==
               rows("SELECT count(*) FROM notifications WHERE user_id=$1", [c.import.user_id])

      assert Processed.done?(ScratchRepo, c.job.args["event_id"])
      assert [] == rows("SELECT kind FROM phoenix.rails_commands")
      assert_receive :imports_changed
      refute_receive :imports_changed
      assert :ok == ProcessGpxWorker.perform(c.job)
      refute_receive :imports_changed

      assert [[1]] ==
               rows("SELECT count(*) FROM notifications WHERE user_id=$1", [c.import.user_id])
    end

    @tag review_case: "zip-#{mode}"
    test "edited partial ZIP cannot settle its parent before pending children in #{mode}", c do
      own_all()
      System.put_env("DAWARICH_RAILS", unquote(mode))

      c =
        Map.merge(
          c,
          Dawarich.Test.NormalFormats.whole!(
            "zip_extractor_later_child_failure",
            ScratchRepo,
            c.root
          )
        )

      start_oban(__MODULE__)
      assert {:snooze, 5} == ProcessWorker.perform(c.job)

      assert [[child, "queued"]] =
               rows(
                 "SELECT child_id,phase FROM phoenix.import_archive_children WHERE parent_id=$1 AND child_id IS NOT NULL",
                 [c.import.id]
               )

      assert [[0]] == rows("SELECT status FROM imports WHERE id=$1", [child])

      assert {:ok, :updated} ==
               Dawarich.Imports.UiRecords.update(ScratchRepo, c.import.user_id, c.import.id, %{
                 "source" => "user_data_archive"
               })

      result = ProcessWorker.perform(c.job)
      assert [[0]] == rows("SELECT status FROM imports WHERE id=$1", [child])
      assert {:snooze, 5} == result
      refute Processed.done?(ScratchRepo, c.job.args["event_id"])
      assert [[1]] == rows("SELECT status FROM imports WHERE id=$1", [c.import.id])
      assert [] == rows("SELECT id FROM notifications WHERE user_id=$1", [c.import.user_id])
      assert {:snooze, 5} == ProcessWorker.perform(c.job)
      refute Processed.done?(ScratchRepo, c.job.args["event_id"])

      if unquote(mode) == "on",
        do:
          assert(
            %{dispatched: 1} =
              Dawarich.Jobs.Dispatch.run(
                now: Dawarich.JobsCase.db_now(ScratchRepo),
                repo: ScratchRepo,
                oban: __MODULE__
              )
          )

      assert [[id, args, worker]] =
               rows(
                 "UPDATE oban.oban_jobs SET state='executing',attempt=1 WHERE args->>'import_id'=$1 RETURNING id,args,worker",
                 [to_string(child)]
               )

      assert :ok ==
               ProcessWorker.perform(%Oban.Job{id: id, args: args, worker: worker, attempt: 1})

      assert [[status]] = rows("SELECT status FROM imports WHERE id=$1", [child])
      assert status in [2, 3]
      Events.subscribe(c.import.user_id)
      flush_progress()
      assert :ok == ProcessWorker.perform(c.job)
      assert [[3]] == rows("SELECT status FROM imports WHERE id=$1", [c.import.id])
      assert Processed.done?(ScratchRepo, c.job.args["event_id"])
      assert_receive :imports_changed

      assert [[1]] ==
               rows("SELECT count(*) FROM notifications WHERE user_id=$1 AND kind=2", [
                 c.import.user_id
               ])

      assert [] == rows("SELECT kind FROM phoenix.rails_commands")
      assert :ok == ProcessWorker.perform(c.job)
      refute_receive :imports_changed

      assert [[1]] ==
               rows("SELECT count(*) FROM notifications WHERE user_id=$1 AND kind=2", [
                 c.import.user_id
               ])
    end
  end

  defp reject_settlement(c) do
    rows("""
    CREATE FUNCTION public.reject_accepted_settlement() RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN RAISE EXCEPTION 'rejected accepted settlement'; END $$
    """)

    rows(
      "CREATE TRIGGER reject_accepted_settlement BEFORE INSERT ON phoenix.processed_commands FOR EACH ROW EXECUTE FUNCTION public.reject_accepted_settlement()"
    )

    try do
      assert_raise Postgrex.Error, fn -> ProcessGpxWorker.perform(c.job) end
      assert [[0]] == rows("SELECT status FROM imports WHERE id=$1", [c.import.id])
      assert [] == rows("SELECT id FROM notifications WHERE user_id=$1", [c.import.user_id])
      refute Processed.done?(ScratchRepo, c.job.args["event_id"])
      refute_receive :imports_changed
    after
      rows("DROP TRIGGER reject_accepted_settlement ON phoenix.processed_commands")
      rows("DROP FUNCTION public.reject_accepted_settlement()")
    end
  end

  defp flush_progress do
    receive do
      :imports_changed -> flush_progress()
    after
      0 -> :ok
    end
  end

  defp normal(c) do
    rows("UPDATE oban.oban_jobs SET worker='Dawarich.Imports.ProcessWorker' WHERE id=$1", [
      c.job.id
    ])

    %{c | job: %{c.job | worker: "Dawarich.Imports.ProcessWorker"}}
  end

  defp own_all do
    for entry <- Registry.entries(), do: Ownership.put!(ScratchRepo, entry.key, :oban)
  end
end

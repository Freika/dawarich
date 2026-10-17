defmodule Dawarich.Imports.StaleRecoveryTest do
  use Dawarich.JobsCase, async: false
  alias Dawarich.Imports.StaleRecovery
  alias Dawarich.Jobs.Ownership
  alias Dawarich.Test.NormalFormats
  @now ~N[2026-01-15 23:30:00]

  setup do
    Ownership.put!(ScratchRepo, "cron:stale_jobs_recovery_job", :oban)
    NormalFormats.seed!("producers/stale/success", ScratchRepo)
  end

  test "stale monitor preserves cutoffs errors and one notification", c do
    import!(987_201, "stale.csv", 25_200)
    import!(987_202, "recent.csv", 7200)
    import!(987_203, "boundary.csv", 21_600)
    import!(987_204, "completed.csv", 25_200, 2)
    import!(987_205, "leased.csv", 25_200)
    foreign_lease!("import:987205")
    import!(987_206, "attempt.csv", 25_200)
    executing_import!(987_206)
    export!(987_601, "stale.json", 10_800)
    export!(987_602, "boundary.json", 7200)
    export!(987_603, "completed.json", 10_800, 2)
    assert :ok = StaleRecovery.run(ScratchRepo, @now)

    assert rows("SELECT name,status,error_message FROM imports ORDER BY id") == [
             ["stale.csv", 3, hd(c.expected["imports"])["error_message"]],
             ["recent.csv", 1, nil],
             ["boundary.csv", 1, nil],
             ["completed.csv", 2, nil],
             ["leased.csv", 1, nil],
             ["attempt.csv", 1, nil]
           ]

    assert rows("SELECT name,status,error_message FROM exports ORDER BY id") == [
             ["stale.json", 3, hd(c.expected["result"]["exports"])["error_message"]],
             ["boundary.json", 1, nil],
             ["completed.json", 2, nil]
           ]

    assert rows(
             "SELECT title,content,CASE kind WHEN 2 THEN 'error' END FROM notifications ORDER BY id"
           ) == c.expected["notifications"]

    assert :ok = StaleRecovery.run(ScratchRepo, @now)
    assert rows("SELECT count(*) FROM notifications") == [[2]]
  end

  test "stale and export monitors cannot both emit for the same owned row", c do
    export!(987_601, "stale.json", 10_800)
    Ownership.put!(ScratchRepo, "cron:stale_jobs_recovery_job", :sidekiq)
    assert :ok = StaleRecovery.run(ScratchRepo, @now)
    assert rows("SELECT status FROM exports") == [[1]]
    assert rows("SELECT count(*) FROM notifications") == [[0]]
    Ownership.put!(ScratchRepo, "cron:stale_jobs_recovery_job", :oban)
    tasks = for _ <- 1..2, do: Task.async(fn -> StaleRecovery.run(ScratchRepo, @now) end)
    assert Enum.map(tasks, &Task.await/1) == [:ok, :ok]
    assert rows("SELECT count(*) FROM notifications") == [[1]]
    [title, content, "error"] = hd(c.expected["notifications"])
    assert rows("SELECT title,content FROM notifications") == [[title, content]]
    old = Ecto.UUID.generate()

    rows(
      "INSERT INTO phoenix.export_claims(export_id,event_id,claimed_at) VALUES(987601,$1,now())",
      [Ecto.UUID.dump!(old)]
    )

    export = %{id: 987_601, user_id: c.user_id}
    blob = %{key: "unused"}

    assert :lost =
             Dawarich.Exports.complete(
               ScratchRepo,
               export,
               old,
               blob,
               %{title: "obsolete", content: "obsolete"},
               @now
             )

    assert rows("SELECT count(*) FROM notifications") == [[1]]
  end

  defp import!(id, name, age, status \\ 1) do
    rows(
      "INSERT INTO imports(id,user_id,name,source,status,additional_data_extraction_status,processing_started_at,created_at,updated_at) VALUES($1,987001,$2,10,$3,5,$4,$5,$5)",
      [id, name, status, NaiveDateTime.add(@now, -age), @now]
    )
  end

  defp export!(id, name, age, status \\ 1) do
    rows(
      "INSERT INTO exports(id,user_id,name,status,processing_started_at,created_at,updated_at) VALUES($1,987001,$2,$3,$4,$5,$5)",
      [id, name, status, NaiveDateTime.add(@now, -age), @now]
    )
  end

  defp executing_import!(id) do
    event = Ecto.UUID.generate()

    job = %{
      "event_id" => event,
      "import_id" => id,
      "user_id" => 987_001,
      "time_zone" => "Europe/Berlin"
    }

    [[job_id]] =
      rows(
        "INSERT INTO oban.oban_jobs(state,queue,worker,args,attempt,max_attempts,inserted_at,scheduled_at,attempted_at) VALUES('executing','imports','Dawarich.Imports.ProcessWorker',$1,1,5,now(),now(),now()) RETURNING id",
        [job]
      )

    rows(
      "INSERT INTO phoenix.import_runs(import_id,user_id,event_id,job_id,attempt,token) VALUES($1,987001,$2,$3,1,$4)",
      [id, Ecto.UUID.dump!(event), job_id, Ecto.UUID.dump!(Ecto.UUID.generate())]
    )
  end
end

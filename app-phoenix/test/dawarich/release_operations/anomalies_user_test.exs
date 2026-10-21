defmodule Dawarich.ReleaseOperations.AnomaliesUserTest do
  use Dawarich.JobsCase

  alias Dawarich.RecalculationFixtures, as: Fixtures
  alias Dawarich.ReleaseOperations, as: Ops
  alias Dawarich.ReleaseOperations.AnomaliesUser, as: Worker

  @now ~U[2026-10-03 12:00:00Z]
  @done "anomaly_rules_recalculated_at"
  @failed "anomaly_rules_recalculation_failed_at"

  setup do
    pool =
      start_supervised!({ScratchRepo, [name: nil, pool_size: 2, parameters: [timezone: "UTC"]]},
        id: :utc_fleet
      )

    ScratchRepo.put_dynamic_repo(pool)
    on_exit(fn -> ScratchRepo.put_dynamic_repo(ScratchRepo) end)
    start_oban(:anomaly_fleet_user)
    :ok
  end

  test "releases exactly one slot on terminal paths and keeps it through bounded retries" do
    for name <- ~w(fleet_missing fleet_done fleet_disabled fleet_interrupted) do
      reset!(ScratchRepo)
      Fixtures.load!(ScratchRepo, Fixtures.case!(name))
      flags = rows("SELECT id,anomaly FROM points ORDER BY id")
      args = args()
      opts = if name == "fleet_interrupted", do: [after_month: fn _ -> :interrupted end], else: []
      assert run(args, opts) == :ok
      assert run(args, opts) == :ok
      assert length(slots()) == 1
      assert rows("SELECT count(*) FROM notifications") == [[0]]

      if name == "fleet_disabled",
        do: assert(rows("SELECT id,anomaly FROM points ORDER BY id") == flags)

      if name == "fleet_interrupted" do
        assert rows("SELECT settings ? $1 FROM users", [@done]) == [[false]]

        assert rows(
                 "SELECT count(*) FROM oban.oban_jobs WHERE worker='Dawarich.Points.AnomalyBackfillWorker'"
               ) == [[1]]
      end
    end

    reset!(ScratchRepo)
    Fixtures.load!(ScratchRepo, Fixtures.case!("fleet_busy"))
    hold_lease!(ScratchRepo, "anomaly_backfill:170101", "other")
    args = args()
    assert run(args, lease: [timeout_ms: 0]) == :ok
    assert slots() == []

    assert [[next, delay]] =
             rows(
               "SELECT args,extract(epoch FROM scheduled_at-inserted_at)::int FROM oban.oban_jobs"
             )

    assert delay == 900
    assert next["cursor"]["request"]["attempt"] == 2
    rows("DELETE FROM oban.oban_jobs")
    final = args(8)
    assert run(final, lease: [timeout_ms: 0]) == :ok
    assert length(slots()) == 1
    assert rows("SELECT settings ? $1 FROM users", [@failed]) == [[true]]
    rows("UPDATE users SET settings=settings || $1", [%{@done => "finished"}])
    assert Worker.mark_failed(ScratchRepo, 170_101, @now) == 0
    assert rows("SELECT settings->>$1 FROM users", [@done]) == [["finished"]]

    reset!(ScratchRepo)
    source = Fixtures.case!("fleet_success")
    Fixtures.load!(ScratchRepo, source)
    args = args()
    failed = [phase: fn :tracks, _, _ -> raise "rebuild_failure" end]
    assert run(args, failed) == :ok
    assert slots() == []
    assert [[next]] = rows("SELECT args FROM oban.oban_jobs")
    assert next["cursor"]["rebuild_attempt"] == 2
    assert run(next, failed) == :ok
    [[last]] = rows("SELECT args FROM oban.oban_jobs ORDER BY id DESC LIMIT 1")
    assert last["cursor"]["rebuild_attempt"] == 3
    assert run(last, failed) == :ok
    assert length(slots()) == 1

    assert rows("SELECT settings ? $1,settings ? $2 FROM users", [@failed, @done]) == [
             [true, false]
           ]

    rows("DELETE FROM oban.oban_jobs")
    manual = args()
    assert run(manual) == :ok

    assert rows("SELECT settings ? $1,settings ? $2 FROM users", [@failed, @done]) == [
             [true, true]
           ]

    assert rows("SELECT count(*) FROM digests") == [[2]]

    assert rows("SELECT kind,title,content FROM notifications") ==
             Enum.map(source["expected"]["notifications"], fn [_, title, content] ->
               [0, title, content]
             end)

    assert length(slots()) == 1
    assert run(manual) == :ok
    assert rows("SELECT count(*) FROM notifications") == [[1]]

    reset!(ScratchRepo)
    Fixtures.load!(ScratchRepo, Fixtures.case!("fleet_done_empty"))
    args = args()
    assert run(args, before_terminal: fn -> raise "terminal" end) == :ok
    assert rows("SELECT settings->>$1 FROM users", [@done]) == [[""]]
    assert rows("SELECT count(*) FROM notifications") == [[0]]
    assert slots() == []

    [[retry]] =
      rows(
        "SELECT args FROM oban.oban_jobs WHERE worker='Dawarich.ReleaseOperations.AnomaliesUser'"
      )

    assert run(retry) == :ok
    assert length(slots()) == 1
    assert rows("SELECT settings->>$1 FROM users", [@done]) == [["2026-10-03T14:00:00+02:00"]]
    assert rows("SELECT count(*) FROM notifications") == [[1]]
  end

  test "a busy successor resets the rebuild budget after an earlier error" do
    source = Fixtures.corpus()["mixed_retries"]
    Fixtures.load!(ScratchRepo, source)
    failed = [phase: fn :tracks, _, _ -> raise "rebuild_failure" end]
    args = args()
    assert run(args, failed) == :ok
    next = assert_retry_step(source, 0)
    assert next["cursor"]["rebuild_attempt"] == 2
    hold_lease!(ScratchRepo, "anomaly_backfill:170101", "other")
    assert run(next, lease: [timeout_ms: 0]) == :ok
    next = assert_retry_step(source, 1)
    assert next["cursor"]["request"]["attempt"] == 2
    assert next["cursor"]["rebuild_attempt"] == 1
    rows("DELETE FROM phoenix.leases WHERE holder='other'")

    Enum.reduce(2..4, next, fn index, current ->
      assert run(current, failed) == :ok
      assert_retry_step(source, index)
    end)
  end

  defp assert_retry_step(source, index) do
    step = Enum.at(source["steps"], index)
    assert rows("SELECT settings ? $1 FROM users", [@failed]) == [[step["failed"]]]
    assert length(slots()) == step["slots"]

    result =
      if step["delay"] do
        assert [[next, delay]] =
                 rows(
                   "SELECT args,extract(epoch FROM scheduled_at-inserted_at)::int FROM oban.oban_jobs"
                 )

        assert delay == step["delay"]
        next
      end

    rows("DELETE FROM oban.oban_jobs")
    result
  end

  defp args(attempt \\ 1) do
    id = Ecto.UUID.generate()

    {:ok, decoded} =
      Worker.args_from_command(1, %{
        "user_id" => 170_101,
        "attempt" => attempt,
        "source_job_id" => id,
        "ambient_zone" => "Europe/Berlin"
      })

    Map.put(decoded, "event_id", id)
  end

  defp run(args, opts \\ []),
    do:
      Ops.run(
        ScratchRepo,
        :anomaly_fleet_user,
        Worker,
        %Oban.Job{args: args, attempt: 1, max_attempts: 26},
        Keyword.merge(
          [now: @now, env: %{"SELF_HOSTED" => "false"}, jitter_draw: 0.0],
          opts
        )
      )

  defp slots,
    do:
      rows("SELECT args FROM oban.oban_jobs WHERE worker='Dawarich.ReleaseOperations.Anomalies'")
end

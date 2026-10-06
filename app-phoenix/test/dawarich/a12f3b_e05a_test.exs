defmodule Dawarich.A12f3bE05ATest do
  use Dawarich.JobsCase

  alias Dawarich.Achievements.{BulkCheck, CheckWorker}
  alias Dawarich.Jobs.Ownership
  alias Dawarich.StatsFixtures, as: F
  @oban __MODULE__.Oban
  @now ~U[2026-10-04 12:00:00.123456Z]

  setup do
    start_oban(@oban)
    F.reset!()
    on_exit(fn -> F.reset!() end)
    :ok
  end

  @tag a12f3b_case: "E05Aa"
  test "E05A native source shapes reach their terminal effects" do
    F.user!(701, %{"locale" => "fr"})
    F.point!(7011, 701, F.ts(2025, 3, 1))
    Ownership.put!(ScratchRepo, "command:achievements.check", :oban)

    args = %{
      "event_id" => Ecto.UUID.generate(),
      "notify" => false,
      "force" => true,
      "stale_only" => false
    }

    assert BulkCheck.run(ScratchRepo, @oban, args, now: @now) == :ok
    assert [[child, at]] = rows("SELECT args, scheduled_at FROM oban.oban_jobs")

    assert child == %{
             "user_id" => 701,
             "notify" => false,
             "oldest_timestamp" => nil,
             "event_id" => BulkCheck.child_id(args["event_id"], 701)
           }

    assert at == DateTime.to_naive(@now)
    assert CheckWorker.perform(%Oban.Job{args: child}) == :ok

    assert [[3]] =
             rows(
               "SELECT (state->>'calculation_version')::integer FROM achievement_progresses WHERE user_id=701 AND achievement_key='exploration'"
             )

    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]

    Ownership.put!(ScratchRepo, "command:achievements.check", :sidekiq)
    handed = Map.put(args, "event_id", Ecto.UUID.generate())
    assert BulkCheck.run(ScratchRepo, @oban, handed, now: @now) == :ok
    assert [[payload]] = rows("SELECT payload FROM phoenix.rails_commands")
    assert payload["force"] == true
    assert payload["notify"] == false
    assert payload["event_id"] == BulkCheck.child_id(handed["event_id"], 701)
    assert DateTime.from_iso8601(payload["run_at"]) == {:ok, @now, 0}
  end
end

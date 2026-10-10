defmodule Dawarich.A12f3bE05BTest do
  use Dawarich.JobsCase

  alias Dawarich.Jobs.{Drain, Ownership}
  alias Dawarich.Stats.{CalculateMonthWorker, Schedule}
  alias Dawarich.StatsFixtures, as: F
  @oban __MODULE__.Oban

  setup do
    start_oban(@oban)
    for spec <- Dawarich.Redis.cache_child_specs(), do: start_supervised!(spec)
    F.reset!()
    Ownership.put!(ScratchRepo, "command:stats.calculate_month", :oban)
    on_exit(fn -> F.reset!() end)
    :ok
  end

  @tag a12f3b_case: "E05Ba"
  test "E05B native source shapes reach their terminal effects" do
    F.user!(702, %{"timezone" => "Asia/Tokyo", "locale" => "fr"})
    F.point!(7021, 702, F.ts(2025, 3, 1))
    event = Ecto.UUID.generate()

    for {year, month} <- [{"2025", "03"}, {2025, 3}] do
      assert Schedule.calculate(ScratchRepo, 702, year, month, false,
               oban: @oban,
               event_id: event
             ) == :ok
    end

    assert [[args]] = rows("SELECT args FROM oban.oban_jobs")

    assert args == %{
             "user_id" => 702,
             "year" => 2025,
             "month" => 3,
             "notify_on_failure" => false,
             "event_id" => event
           }

    assert CalculateMonthWorker.perform(%Oban.Job{args: args}) == :ok
    assert F.stat(702, 2025, 3)["calculation_version"] == 3
    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]
  end

  @tag a12f3b_case: "E05Bb"
  test "E05B accepted children prevent premature completion" do
    clock = DateTime.to_unix(~U[2030-01-01 00:00:00Z])
    event = Ecto.UUID.generate()
    opts = [oban: @oban, clock: clock, schedule_in: 90, event_id: event]
    assert Schedule.calculate(ScratchRepo, 702, 2025, 3, true, opts) == :ok
    assert [[due, "scheduled"]] = rows("SELECT scheduled_at, state FROM oban.oban_jobs")
    assert due == ~N[2030-01-01 00:01:30.000000]
    assert Schedule.calculate(ScratchRepo, 702, 2025, 3, true, opts) == :ok
    assert Drain.status(ScratchRepo).counts.incomplete_oban == 1
    assert "incomplete_oban" in Drain.status(ScratchRepo).shutdown_reasons

    assert {:error, :child_rollback} =
             ScratchRepo.transaction(fn ->
               assert Schedule.calculate(ScratchRepo, 702, 2025, 4, true, opts) == :ok
               ScratchRepo.rollback(:child_rollback)
             end)

    assert rows("SELECT count(*) FROM oban.oban_jobs") == [[1]]
    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]
  end
end

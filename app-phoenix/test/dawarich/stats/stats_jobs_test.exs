defmodule Dawarich.Stats.StatsJobsTest do
  use Dawarich.JobsCase

  alias Dawarich.Jobs.{Ownership, Registry}
  alias Dawarich.StatsFixtures, as: F
  alias Dawarich.Stats.{BulkSweepWorker, CalculateMonthWorker, Schedule, ToponymsRefreshWorker}

  @oban :a12d1a_stats_oban
  @payload %{"user_id" => 7, "year" => 2024, "month" => 3, "notify_on_failure" => true}

  setup do: F.reset!()

  test "a month goes to Rails with its run_at while Sidekiq owns the calculation" do
    assert Schedule.calculate(ScratchRepo, 7, 2024, 3, false,
             schedule_in: 90,
             clock: 1_790_000_000
           ) == :ok

    assert F.calculations() == [
             %{
               "user_id" => 7,
               "year" => 2024,
               "month" => 3,
               "notify_on_failure" => false,
               "run_at" => 1_790_000_090
             }
           ]

    assert rows("SELECT count(*) FROM oban.oban_jobs") == [[0]]
  end

  test "a month becomes a CalculateMonthWorker job once Oban owns the calculation" do
    start_oban(@oban)
    Ownership.put!(ScratchRepo, "command:stats.calculate_month", :oban)
    assert Schedule.calculate(ScratchRepo, 7, 2024, 3, true, oban: @oban, schedule_in: 60) == :ok

    assert [["Dawarich.Stats.CalculateMonthWorker", @payload, "projections", scheduled_at]] =
             rows("SELECT worker, args, queue, scheduled_at FROM oban.oban_jobs")

    assert NaiveDateTime.diff(scheduled_at, NaiveDateTime.utc_now()) in 50..60
    assert F.calculations() == []
  end

  test "the worker decodes only version-1 payloads of integers and a boolean" do
    assert CalculateMonthWorker.args_from_command(1, @payload) == {:ok, @payload}

    assert CalculateMonthWorker.args_from_command(1, %{@payload | "year" => "2024"}) ==
             {:error, "invalid_payload"}

    assert CalculateMonthWorker.args_from_command(1, Map.put(@payload, "extra", 1)) ==
             {:error, "invalid_payload"}

    assert CalculateMonthWorker.args_from_command(2, @payload) == {:error, "unsupported_version"}
  end

  test "the worker calculates the month it was given" do
    F.user!(31, %{"timezone" => "Etc/UTC"})
    F.point!(3101, 31, F.ts(2024, 3, 1, 12))

    assert CalculateMonthWorker.perform(%Oban.Job{args: %{@payload | "user_id" => 31}}) == :ok
    assert %{"calculation_version" => 3, "year" => 2024, "month" => 3} = F.stat(31, 2024, 3)
  end

  test "the calculation key is registered unclaimable and resolves to the worker" do
    entries = Map.new(Registry.entries(), &{&1.key, &1})

    assert %{kind: :command, worker: CalculateMonthWorker, claimable: false} =
             entries["command:stats.calculate_month"]

    assert Registry.command("stats.calculate_month") == {:ok, CalculateMonthWorker}
    assert Registry.claimable() == []
  end

  test "the toponym cron cancels itself while Sidekiq owns it and runs once Oban does" do
    assert ToponymsRefreshWorker.run(ScratchRepo) == {:cancel, :not_owner}
    assert rows("SELECT count(*) FROM phoenix.cursors") == [[0]]
    Ownership.put!(ScratchRepo, ToponymsRefreshWorker.key(), :oban)
    assert ToponymsRefreshWorker.run(ScratchRepo) == :ok

    assert rows(
             "SELECT value FROM phoenix.cursors WHERE key = 'stats:toponyms_reconciliation:turn'"
           ) ==
             [["1"]]
  end

  test "the toponym cron skips a run while another runtime holds the refresh lease" do
    Ownership.put!(ScratchRepo, ToponymsRefreshWorker.key(), :oban)
    foreign_lease!("stats:toponyms_refresh")
    waited = fn _ms -> flunk("the toponym cron waited for the refresh lease") end
    assert ToponymsRefreshWorker.run(ScratchRepo, sleep: waited) == :ok
    assert rows("SELECT count(*) FROM phoenix.cursors") == [[0]]
  end

  test "the toponym cron is registered unclaimable on Rails' schedule" do
    entry = Enum.find(Registry.entries(), &(&1.key == "cron:stats_toponyms_refresh_job"))

    assert %{
             kind: :cron,
             worker: ToponymsRefreshWorker,
             claimable: false,
             expression: "*/5 * * * *"
           } = entry

    assert Dawarich.RailsTree.read("config/schedule.yml") =~
             ~r/stats_toponyms_refresh_job:\n\s+cron: "\*\/5 \* \* \* \*"/

    assert {"*/5 * * * *", ToponymsRefreshWorker} in Registry.crontab()
  end

  test "the hourly sweep cancels itself while Sidekiq owns it" do
    assert BulkSweepWorker.run(ScratchRepo) == {:cancel, :not_owner}
  end

  test "the hourly sweep fails only when every active or trial user failed" do
    Ownership.put!(ScratchRepo, BulkSweepWorker.key(), :oban)
    F.user!(41, %{})
    F.user!(42, %{}, %{"status" => 2})
    F.user!(43, %{}, %{"status" => 0})
    seen = :ets.new(:seen, [:public, :bag])
    boom = fn _repo, id, _opts -> :ets.insert(seen, {id}) && raise("boom") end

    ExUnit.CaptureLog.capture_log(fn ->
      assert BulkSweepWorker.run(ScratchRepo, calculator: boom) ==
               {:error, "stats calculation failed for all 2 users"}
    end)

    assert :ets.tab2list(seen) |> Enum.sort() == [{41}, {42}]
    one = fn _repo, id, _opts -> if id == 41, do: raise("boom"), else: :ok end

    ExUnit.CaptureLog.capture_log(fn ->
      assert BulkSweepWorker.run(ScratchRepo, calculator: one) == :ok
    end)
  end

  test "the hourly sweep is registered unclaimable on Rails' schedule" do
    entry = Enum.find(Registry.entries(), &(&1.key == "cron:bulk_stats_calculating_job"))

    assert %{kind: :cron, worker: BulkSweepWorker, claimable: false, expression: "0 */1 * * *"} =
             entry

    assert Dawarich.RailsTree.read("config/schedule.yml") =~
             ~r/bulk_stats_calculating_job:\n\s+cron: "0 \*\/1 \* \* \*"/
  end
end

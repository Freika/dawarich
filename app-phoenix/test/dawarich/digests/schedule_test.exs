defmodule Dawarich.Digests.ScheduleTest do
  use Dawarich.JobsCase

  alias Dawarich.Digests.{MonthlyWorker, Schedule, YearlyWorker}
  alias Dawarich.Jobs.Ownership

  test "digest follow-ups route once to Oban or Rails with the exact due time and zone" do
    oban = start_oban(__MODULE__)
    assert is_pid(oban)
    at = ~U[2030-03-29 12:34:56.123456Z]
    opts = [oban: __MODULE__, scheduled_at: at]

    for {period, worker} <- [{"month", MonthlyWorker}, {"year", YearlyWorker}] do
      type = "digests.calculate_" <> period
      payload = %{"user_id" => 42, "year" => 2025, "time_zone" => "Tokyo"}
      payload = if period == "month", do: Map.put(payload, "month", 3), else: payload
      Ownership.put!(ScratchRepo, "cron:#{period}ly_digest_scheduling_job", :oban)

      for owner <- [nil, :sidekiq, :oban] do
        Dawarich.FixtureCleanup.delete!(ScratchRepo, ~w(phoenix.rails_commands  oban.oban_jobs))
        if owner, do: Ownership.put!(ScratchRepo, "command:" <> type, owner)
        assert enqueue(period, opts) == :ok

        if owner == :oban do
          assert [[0]] = rows("SELECT count(*) FROM phoenix.rails_commands")

          assert [[name, args, due, queue, attempts]] =
                   rows("SELECT worker,args,scheduled_at,queue,max_attempts FROM oban.oban_jobs")

          assert name == String.replace_prefix(to_string(worker), "Elixir.", "")
          assert Map.delete(args, "event_id") == payload
          assert Ecto.UUID.cast(args["event_id"]) == {:ok, args["event_id"]}
          assert due == DateTime.to_naive(at)
          assert queue == "projections"
          assert attempts == 3
        else
          assert [[0]] = rows("SELECT count(*) FROM oban.oban_jobs")
          assert [[^type, reverse]] = rows("SELECT kind,payload FROM phoenix.rails_commands")
          assert Map.delete(reverse, "run_at") == payload
          assert reverse["run_at"] == DateTime.to_unix(at, :microsecond) / 1_000_000
        end

        Dawarich.FixtureCleanup.delete!(ScratchRepo, ~w(phoenix.rails_commands  oban.oban_jobs))

        assert {:error, :caller_rollback} =
                 ScratchRepo.transaction(fn ->
                   assert enqueue(period, opts) == :ok
                   ScratchRepo.rollback(:caller_rollback)
                 end)

        assert [[0]] = rows("SELECT count(*) FROM phoenix.rails_commands")
        assert [[0]] = rows("SELECT count(*) FROM oban.oban_jobs")
      end
    end
  end

  defp enqueue("month", opts), do: Schedule.monthly(ScratchRepo, 42, 2025, 3, "Tokyo", opts)
  defp enqueue("year", opts), do: Schedule.yearly(ScratchRepo, 42, 2025, "Tokyo", opts)
end

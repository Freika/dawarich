defmodule Dawarich.Digests.SchedulingTest do
  use Dawarich.JobsCase

  alias Dawarich.Digests.Scheduling
  alias Dawarich.Digests.{MonthlyScheduleWorker, YearlyScheduleWorker}
  alias Dawarich.Jobs.Ownership

  test "both digest crons gate each eligible batch and stop future enqueue effects on release" do
    start_oban(__MODULE__)

    for {kind, worker, command} <- [
          {"monthly", MonthlyScheduleWorker, "digests.calculate_month"},
          {"yearly", YearlyScheduleWorker, "digests.calculate_year"}
        ] do
      row = Enum.find(corpus()["schedulers"], &(&1["id"] == "two_batches_" <> kind))
      {:ok, now, 0} = DateTime.from_iso8601(row["now"])
      opts = [now: now, zone: row["ambient_zone"]]
      job = %Oban.Job{conf: %Oban.Config{name: __MODULE__}}
      key = "cron:#{kind}_digest_scheduling_job"
      reset!(ScratchRepo)
      Dawarich.DigestFixtures.load_scheduler!(ScratchRepo, row)
      Ownership.put!(ScratchRepo, "command:" <> command, :oban)

      for owner <- [nil, :sidekiq] do
        if owner, do: Ownership.put!(ScratchRepo, key, owner)
        assert worker.perform(job, opts) == {:cancel, :not_owner}
        assert [[0]] = rows("SELECT count(*) FROM oban.oban_jobs")
        assert [[0]] = rows("SELECT count(*) FROM phoenix.rails_commands")
      end

      Ownership.put!(ScratchRepo, key, :oban)
      assert worker.perform(job, opts) == :ok
      actual = rows("SELECT args FROM oban.oban_jobs ORDER BY (args->>'user_id')::integer")
      expected = Enum.map(row["jobs"], &hd(&1["arguments"]))
      assert Enum.map(actual, fn [args] -> args["user_id"] end) == expected

      for [args] <- actual do
        assert args["year"] == row["period"]["year"]
        assert args["month"] == row["period"]["month"]
        assert args["time_zone"] == row["ambient_zone"]
      end

      assert worker.perform(job, opts) == :ok
      assert [[count]] = rows("SELECT count(*) FROM oban.oban_jobs")
      assert count == 2 * length(expected)
      Dawarich.FixtureCleanup.delete!(ScratchRepo, ~w(oban.oban_jobs))
      parent = self()

      release = fn cursor ->
        task =
          Task.async(fn ->
            Ownership.put!(ScratchRepo, key, :sidekiq)
            send(parent, {:released, cursor})
          end)

        Task.await(task)
        assert_receive {:released, ^cursor}
      end

      assert worker.perform(job, Keyword.put(opts, :after_batch, release)) ==
               {:cancel, :not_owner}

      {first, _} =
        Scheduling.batch(
          ScratchRepo,
          kind,
          row["period"] |> Map.new(fn {k, v} -> {String.to_existing_atom(k), v} end)
        )

      assert [[count]] = rows("SELECT count(*) FROM oban.oban_jobs")
      assert count == length(first)
      assert count < length(expected)
      assert [[0]] = rows("SELECT count(*) FROM oban.oban_jobs WHERE state='cancelled'")
    end
  end

  test "digest target periods use the serialized ambient calendar" do
    for row <- corpus()["schedulers"] do
      {:ok, now, 0} = DateTime.from_iso8601(row["now"])
      period = Scheduling.period(ScratchRepo, row["kind"], now, row["ambient_zone"])

      assert period.year == row["period"]["year"], row["id"]
      assert period.month == row["period"]["month"], row["id"]
    end

    now = ~U[2025-01-31 23:30:00Z]
    assert Scheduling.period(ScratchRepo, "monthly", now) == %{year: 2025, month: 1}

    assert Scheduling.period(ScratchRepo, "monthly", now, "Tokyo") ==
             Scheduling.period(ScratchRepo, "monthly", now, "Asia/Tokyo")
  end

  defp corpus do
    __DIR__
    |> Path.join("../../fixtures/a12d1b2/jobs.json")
    |> File.read!()
    |> Jason.decode!()
  end

  test "digest candidates match Rails find_each eligibility across two batches" do
    for row <- corpus()["schedulers"] do
      reset!(ScratchRepo)
      Dawarich.DigestFixtures.load_scheduler!(ScratchRepo, row)
      period = %{year: row["period"]["year"], month: row["period"]["month"]}
      {first, cursor} = Scheduling.batch(ScratchRepo, row["kind"], period, 0)
      {second, next_cursor} = Scheduling.batch(ScratchRepo, row["kind"], period, cursor)
      {[], nil} = Scheduling.batch(ScratchRepo, row["kind"], period, next_cursor || cursor)
      expected = Enum.map(row["jobs"], &hd(&1["arguments"]))

      assert Enum.map(first ++ second, & &1.id) == expected, row["id"]
      assert length(first) <= 1000
      assert Enum.all?(first, &(&1.id <= cursor))
      assert Enum.all?(second, &(&1.id > cursor))

      if String.starts_with?(row["id"], "two_batches") do
        assert length(expected) > 1000
        assert second != []
        assert next_cursor == List.last(row["users"])["id"]
      else
        assert second == []
        assert next_cursor == nil
      end
    end
  end
end

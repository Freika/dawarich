defmodule Dawarich.Stats.FullRecalculationTest do
  use Dawarich.JobsCase

  alias Dawarich.Jobs.{Ownership, Processed}
  alias Dawarich.RecalculationFixtures, as: Fixtures
  alias Dawarich.Stats.{FullRecalculation, FullRecalculationWorker, TrackedMonths}
  alias Dawarich.State

  @user_id 170_101
  @key "stats_full_recalculation:user:170101"

  test "clears K5 even for missing users and schedules tracked months once" do
    oban = :full_stats
    start_oban(oban)
    source_id = Fixtures.case!("full")["job"]["job_id"]
    payload = %{"user_id" => @user_id, "source_job_id" => source_id}
    assert FullRecalculationWorker.args_from_command(1, payload) == {:ok, payload}
    assert FullRecalculationWorker.new(payload).changes.queue == "projections"

    for owner <- [:sidekiq, :oban], id <- ~w(full full_missing full_deleted) do
      reset!(ScratchRepo)
      kase = Fixtures.case!(id)
      Fixtures.load!(ScratchRepo, kase)
      Ownership.put!(ScratchRepo, "command:stats.calculate_month", owner)
      assert State.debounce(ScratchRepo, @key, 300)
      args = Map.put(payload, "event_id", Ecto.UUID.generate())

      {:ok, :ok} =
        ScratchRepo.transaction(fn ->
          rows("SELECT set_config('TimeZone', $1, true)", [kase["database_zone"]])
          assert FullRecalculation.run(ScratchRepo, args, oban: oban, clock: 1_791_028_800) == :ok
          refute State.claimed?(ScratchRepo, @key)
          assert Processed.done?(ScratchRepo, args["event_id"])

          expected =
            for job <- kase["expected"]["jobs"] do
              [user, year, month] = job["arguments"]
              %{"user_id" => user, "year" => year, "month" => month, "notify_on_failure" => true}
            end

          assert children(owner) == expected
          assert FullRecalculation.run(ScratchRepo, args, oban: oban, clock: 1_791_028_800) == :ok
          assert children(owner) == expected
          :ok
        end)
    end
  end

  test "fanout failure rolls back clear and children while replay keeps later claims" do
    oban = :full_stats_rollback
    start_oban(oban)

    for owner <- [:sidekiq, :oban] do
      reset!(ScratchRepo)
      kase = Fixtures.case!("full")
      Fixtures.load!(ScratchRepo, kase)
      Ownership.put!(ScratchRepo, "command:stats.calculate_month", owner)

      args = %{
        "user_id" => @user_id,
        "source_job_id" => kase["job"]["job_id"],
        "event_id" => Ecto.UUID.generate()
      }

      assert State.debounce(ScratchRepo, @key, 300)
      before = rows("SELECT expires_at FROM phoenix.once_claims WHERE key=$1", [@key])

      hook = fn _year, _month ->
        assert length(children(owner)) == 1
        refute State.claimed?(ScratchRepo, @key)
        assert Processed.done?(ScratchRepo, args["event_id"])
        raise "synthetic fanout failure"
      end

      assert_raise RuntimeError, "synthetic fanout failure", fn ->
        FullRecalculation.run(ScratchRepo, args, oban: oban, after_child: hook)
      end

      assert rows("SELECT expires_at FROM phoenix.once_claims WHERE key=$1", [@key]) == before
      assert children(owner) == []
      refute Processed.done?(ScratchRepo, args["event_id"])
      assert FullRecalculation.run(ScratchRepo, args, oban: oban) == :ok
      count = Enum.reduce(TrackedMonths.call(ScratchRepo, @user_id), 0, &(length(&1.months) + &2))
      assert length(children(owner)) == count
      refute State.claimed?(ScratchRepo, @key)
      assert State.debounce(ScratchRepo, @key, 300)
      later = rows("SELECT expires_at FROM phoenix.once_claims WHERE key=$1", [@key])
      assert FullRecalculation.run(ScratchRepo, args, oban: oban) == :ok
      assert rows("SELECT expires_at FROM phoenix.once_claims WHERE key=$1", [@key]) == later
      assert length(children(owner)) == count
      fresh = Map.put(args, "event_id", Ecto.UUID.generate())
      assert FullRecalculation.run(ScratchRepo, fresh, oban: oban) == :ok
      refute State.claimed?(ScratchRepo, @key)
      assert length(children(owner)) == count * 2
    end
  end

  defp children(:sidekiq),
    do:
      rows(
        "SELECT payload - 'run_at' FROM phoenix.rails_commands WHERE kind='stats.calculate_month' ORDER BY id"
      )
      |> Enum.map(&hd/1)

  defp children(:oban),
    do:
      rows(
        "SELECT args - 'event_id' FROM oban.oban_jobs WHERE worker='Dawarich.Stats.CalculateMonthWorker' ORDER BY id"
      )
      |> Enum.map(&hd/1)
end

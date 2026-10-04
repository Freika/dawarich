defmodule Dawarich.Digests.RunTest do
  use Dawarich.JobsCase

  alias Dawarich.DigestFixtures
  alias Dawarich.Digests.{Calculation, Run}

  @now ~U[2026-10-03 12:00:00Z]

  test "yearly generation visits all twelve months in order and keeps earlier committed stats on a later raised error" do
    kase = job_case!("new_yearly_en")
    DigestFixtures.load!(ScratchRepo, kase)
    caller = self()

    stats = fn repo, id, year, month, opts ->
      send(caller, {:month, month})
      Dawarich.Stats.CalculateMonth.call(repo, id, year, month, opts)
    end

    opts =
      options(kase)
      |> Keyword.put(:stats, stats)
      |> Keyword.put(:before_store, fn _context -> send(caller, :digest) end)

    assert {:ok, id} = Run.yearly(ScratchRepo, args(kase), opts)

    for month <- 1..12 do
      assert_receive {:month, observed}
      assert observed == month
    end

    assert_receive :digest
    [expected] = kase["expected"]["rows"]
    assert DigestFixtures.digests(ScratchRepo, 14101) == [Map.put(expected, "id", id)]

    reset!(ScratchRepo)
    DigestFixtures.load!(ScratchRepo, kase)
    fault = %RuntimeError{message: "later stats constructor"}

    failing = fn repo, id, year, month, opts ->
      if month == 7, do: raise(fault)
      Dawarich.Stats.CalculateMonth.call(repo, id, year, month, opts)
    end

    assert {:error, ^fault, stack} =
             Run.yearly(ScratchRepo, args(kase), Keyword.put(options(kase), :stats, failing))

    assert stack != []

    assert [[3]] =
             rows(
               "SELECT calculation_version FROM stats WHERE user_id=14101 AND year=2025 AND month=3"
             )

    assert DigestFixtures.digests(ScratchRepo, 14101) == []
  end

  test "monthly generation recalculates stats before persisting the exact digest" do
    for name <- ~w(new_monthly_en existing_monthly_en) do
      reset!(ScratchRepo)
      kase = job_case!(name)
      DigestFixtures.load!(ScratchRepo, kase)
      [expected] = kase["expected"]["rows"]
      args = args(kase)
      opts = options(kase)
      assert {:ok, id} = Run.monthly(ScratchRepo, args, opts)
      assert DigestFixtures.digests(ScratchRepo, 14101) == [Map.put(expected, "id", id)]

      assert [[3]] =
               rows(
                 "SELECT calculation_version FROM stats WHERE user_id=14101 AND year=2025 AND month=3"
               )
    end

    rows("DELETE FROM public.digests WHERE user_id=14101")
    invalid = Keyword.put(options(job_case!("new_monthly_en")), :uuid, "invalid-uuid")

    assert {:error, %ArgumentError{} = original} =
             Calculation.monthly(ScratchRepo, 14101, 2025, 3, invalid)

    assert {:error, ^original, stack} =
             Calculation.monthly(
               ScratchRepo,
               14101,
               2025,
               3,
               Keyword.put(invalid, :error_stack, true)
             )

    assert Enum.any?(stack, &match?({Dawarich.Digests.Store, :save!, _, _}, &1))

    assert {:error, ^original} =
             Calculation.monthly(
               ScratchRepo,
               14101,
               2025,
               3,
               Keyword.put(invalid, :error_stack, false)
             )

    assert {:error, ^original, run_stack} =
             Run.monthly(ScratchRepo, args(job_case!("new_monthly_en")), invalid)

    assert Enum.any?(run_stack, &match?({Dawarich.Digests.Store, :save!, _, _}, &1))
    assert DigestFixtures.digests(ScratchRepo, 14101) == []
  end

  defp job_case!(name) do
    corpus =
      __DIR__
      |> Path.join("../../fixtures/a12d1b2/jobs.json")
      |> File.read!()
      |> Jason.decode!()

    kase =
      Enum.find(corpus["workers"], &(&1["id"] == name)) || raise "missing digest job case #{name}"

    Map.merge(%{"legacy_duplicates" => false, "null_segment_mode" => false}, kase)
  end

  defp args(kase) do
    [id, year | month] = kase["args"]
    base = %{"user_id" => id, "year" => year, "time_zone" => kase["ambient_zone"]}
    if month == [], do: base, else: Map.put(base, "month", hd(month))
  end

  defp options(kase) do
    row = hd(kase["expected"]["rows"])
    [now: @now, env: %{"SELF_HOSTED" => "false", "TIME_ZONE" => "UTC"}, uuid: row["sharing_uuid"]]
  end
end

defmodule Dawarich.Digests.RunTest do
  use Dawarich.JobsCase

  alias Dawarich.DigestFixtures
  alias Dawarich.Digests.{Calculation, Run}

  @now ~U[2026-10-03 12:00:00Z]

  test "generation skips deleted users but continues after an internally reported stats failure" do
    unexpected = fn _, _, _, _, _ -> flunk("calculator ran for missing user") end

    for kind <- ~w(monthly yearly), profile <- ~w(missing_user deleted_user) do
      reset!(ScratchRepo)
      kase = job_case!("#{profile}_#{kind}_en")
      DigestFixtures.load!(ScratchRepo, kase)

      assert apply(Run, String.to_existing_atom(kind), [
               ScratchRepo,
               args(kase),
               [stats: unexpected]
             ]) == :missing
    end

    fault = %RuntimeError{message: "synthetic digest failure"}
    returned = fn _, _, _, _, _ -> {:error, fault} end

    for kind <- ~w(monthly yearly) do
      reset!(ScratchRepo)
      kase = job_case!("stats_return_#{kind}_en")
      DigestFixtures.load!(ScratchRepo, kase)

      assert {:ok, id} =
               apply(Run, String.to_existing_atom(kind), [
                 ScratchRepo,
                 args(kase),
                 Keyword.put(options(kase), :stats, returned)
               ])

      [expected] = kase["expected"]["rows"]
      assert DigestFixtures.digests(ScratchRepo, 14101) == [Map.put(expected, "id", id)]

      raised = fn _, _, _, _, _ -> raise fault end

      assert {:error, ^fault, raised_stack} =
               apply(Run, String.to_existing_atom(kind), [
                 ScratchRepo,
                 args(kase),
                 [stats: raised]
               ])

      assert raised_stack != []

      captured = [{__MODULE__, :digest_origin, 0, [file: ~c"synthetic.ex", line: 7]}]
      monthly = fn _, _, _, _, _ -> {:error, fault, captured} end
      yearly = fn _, _, _, _ -> {:error, fault, captured} end
      opts = [stats: fn _, _, _, _, _ -> :ok end, monthly: monthly, yearly: yearly]

      assert apply(Run, String.to_existing_atom(kind), [ScratchRepo, args(kase), opts]) ==
               {:error, fault, captured}
    end

    assert {:error, :lookup_fault} =
             ScratchRepo.transaction(fn ->
               assert {:error, %Postgrex.Error{}} =
                        ScratchRepo.query("SELECT 1/0", [], log: false)

               assert_raise Postgrex.Error, fn ->
                 Run.monthly(ScratchRepo, %{"user_id" => 14101})
               end

               ScratchRepo.rollback(:lookup_fault)
             end)
  end

  test "returned calculator database errors preserve Rails continuation and terminal failure policy" do
    kase = job_case!("stats_database_monthly_en")
    DigestFixtures.load!(ScratchRepo, kase)
    database_error = %Postgrex.Error{message: "synthetic digest failure"}
    failing_hexagons = fn _, _, _, _ -> raise database_error end
    stats_opts = [now: DateTime.to_naive(@now), hexagons: failing_hexagons]

    assert {:error, ^database_error} =
             Dawarich.Stats.CalculateMonth.call(ScratchRepo, 14101, 2025, 3, stats_opts)

    assert [[1]] = rows("SELECT count(*) FROM notifications WHERE user_id=14101 AND kind=2")

    assert {:ok, id} =
             Run.monthly(
               ScratchRepo,
               args(kase),
               Keyword.put(options(kase), :stats_opts, stats_opts)
             )

    [expected] = kase["expected"]["rows"]
    assert DigestFixtures.digests(ScratchRepo, 14101) == [Map.put(expected, "id", id)]
    assert [[2]] = rows("SELECT count(*) FROM notifications WHERE user_id=14101 AND kind=2")

    before_store = fn _context -> raise database_error end
    opts = Keyword.put(options(kase), :before_store, before_store)

    assert {:error, ^database_error, captured} =
             Calculation.monthly(
               ScratchRepo,
               14101,
               2025,
               3,
               Keyword.put(opts, :error_stack, true)
             )

    assert Enum.any?(captured, &match?({Dawarich.Digests.Calculation, _, _, _}, &1))
    assert {:error, ^database_error, stack} = Run.monthly(ScratchRepo, args(kase), opts)
    assert Enum.any?(stack, &match?({Dawarich.Digests.Calculation, _, _, _}, &1))
    assert stack != []
    assert job_case!("digest_database_monthly_en")["expected"]["emails"] == []
    assert length(kase["expected"]["emails"]) == 1
  end

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

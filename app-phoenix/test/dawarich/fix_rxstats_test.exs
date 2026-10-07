defmodule Dawarich.FixRxStatsTest do
  use Dawarich.JobsCase
  alias Dawarich.StatsFixtures, as: F
  alias Dawarich.DigestFixtures, as: D
  alias Dawarich.Jobs.Ownership
  alias Dawarich.Stats.{Schedule, CalculateMonthWorker}
  @oban __MODULE__.Oban

  setup do
    F.reset!()
    start_oban(@oban)
    for spec <- Dawarich.Redis.cache_child_specs(), do: start_supervised!(spec)
    previous = System.get_env("DAWARICH_RAILS")
    System.delete_env("DAWARICH_RAILS")

    on_exit(fn ->
      if previous,
        do: System.put_env("DAWARICH_RAILS", previous),
        else: System.delete_env("DAWARICH_RAILS")
    end)

    :ok
  end

  @tag a12f3b_case: "RX01"
  test "stable monthly stats event does not execute again on redelivery" do
    for source <- [:event, :legacy] do
      reset!(ScratchRepo)
      F.reset!()
      Ownership.put!(ScratchRepo, "command:stats.calculate_month", :oban)
      F.user!(901, %{"timezone" => "Etc/UTC"})
      F.point!(9011, 901, F.ts(2024, 3, 1, 12))

      F.point!(9012, 901, F.ts(2024, 3, 1, 12, 5), %{
        "lonlat" => "SRID=4326;POINT(12.4731 51.3397)"
      })

      event = Ecto.UUID.generate()

      assert Schedule.calculate(ScratchRepo, 901, 2024, 3, false, oban: @oban, event_id: event) ==
               :ok

      [[args]] = rows("SELECT args FROM oban.oban_jobs")

      job =
        if source == :event do
          %Oban.Job{args: args}
        else
          Oban.insert!(@oban, CalculateMonthWorker.new(Map.delete(args, "event_id")))
        end

      fault = fn -> raise "stats transaction fault" end

      assert {:error, %RuntimeError{message: "stats transaction fault"}} =
               CalculateMonthWorker.perform(job, invalidated: fault)

      assert F.stat(901, 2024, 3) == nil

      assert [[0]] =
               rows(
                 "SELECT count(*) FROM phoenix.processed_commands WHERE handler='stats.calculate_month'"
               )

      assert CalculateMonthWorker.perform(job) == :ok
      first = F.stat(901, 2024, 3)["distance"]
      assert first == 6968
      rows("DELETE FROM points WHERE user_id=$1", [901])
      rows("DELETE FROM oban.oban_jobs")
      assert CalculateMonthWorker.perform(job) == :ok
      assert F.stat(901, 2024, 3)["distance"] == first

      assert [[1]] =
               rows(
                 "SELECT count(*) FROM phoenix.processed_commands WHERE handler='stats.calculate_month'"
               )

      fresh = %Oban.Job{args: Map.put(args, "event_id", Ecto.UUID.generate())}
      assert CalculateMonthWorker.perform(fresh) == :ok
      assert F.stat(901, 2024, 3)["distance"] == 0
    end
  end

  for kind <- [:stats, :monthly, :yearly, :full] do
    @kind kind
    @tag a12f3b_case: "RX02_#{kind}"
    test "stable #{@kind} schedule stays in one runtime after ownership flip" do
      key = key(@kind)

      for owner <- [:oban, :sidekiq] do
        reset!(ScratchRepo)
        event = Ecto.UUID.generate()
        Ownership.put!(ScratchRepo, key, owner)
        assert publish(@kind, event, 901, 2024, 3) == :ok
        other = if owner == :oban, do: :sidekiq, else: :oban
        Ownership.put!(ScratchRepo, key, other)
        for _ <- 1..2, do: assert(publish(@kind, event, 901, 2024, 3) == :ok)
        assert delivery_count() == 1

        if owner == :sidekiq do
          [[payload]] = rows("SELECT payload FROM phoenix.rails_commands")
          refute Map.has_key?(payload, "event_id")
          assert payload["user_id"] == 901
        end

        rows("DELETE FROM oban.oban_jobs")
        rows("DELETE FROM public.job_outbox")
        rows("DELETE FROM phoenix.rails_commands")
        assert publish(@kind, event, 901, 2024, 3) == :ok
        assert delivery_count() == 0
        assert publish(@kind, event, 902, 2024, 3) == :ok
        {next_event, next_year} = next_identity(@kind, event)
        assert publish(@kind, next_event, 901, next_year, 4) == :ok
        assert delivery_count() == 2
      end

      reset!(ScratchRepo)
      event = Ecto.UUID.generate()
      Ownership.put!(ScratchRepo, key, :oban)
      tasks = for _ <- 1..2, do: Task.async(fn -> publish(@kind, event, 901, 2024, 3) end)
      for task <- tasks, do: assert(Task.await(task) == :ok)
      assert delivery_count() == 1
      reset!(ScratchRepo)

      assert {:error, :fault} =
               ScratchRepo.transaction(fn ->
                 assert publish(@kind, event, 901, 2024, 3) == :ok
                 ScratchRepo.rollback(:fault)
               end)

      assert delivery_count() == 0
      assert publish(@kind, event, 901, 2024, 3) == :ok
      assert delivery_count() == 1
    end
  end

  for kind <- [:monthly, :yearly] do
    @kind kind
    @tag a12f3b_case: "RX03_#{kind}"
    test "#{@kind} generation does not recalculate after terminal rollback" do
      kase = D.job_case!("new_#{@kind}_en")
      D.load!(ScratchRepo, kase)
      args = D.job_args(kase)
      Ownership.put!(ScratchRepo, "command:stats.calculate_month", :oban)
      Ownership.put!(ScratchRepo, "command:mail.digest.#{@kind}", :oban)
      counts = :ets.new(:probe_counts, [:public])
      :ets.insert(counts, [{:stats, 0}, {:digests, 0}])

      stats = fn repo, id, year, month, opts ->
        :ets.update_counter(counts, :stats, 1)
        Dawarich.Stats.CalculateMonth.call(repo, id, year, month, opts)
      end

      opts =
        D.job_options(kase) ++
          [stats: stats, after_store: fn _ -> :ets.update_counter(counts, :digests, 1) end]

      fault = fn -> raise "posthoc terminal fault" end

      assert {:error, %RuntimeError{message: "posthoc terminal fault"}} =
               Dawarich.Digests.Generation.run(
                 ScratchRepo,
                 @kind,
                 args,
                 Keyword.put(opts, :after_terminal, fault)
               )

      assert [[2]] =
               rows(
                 "SELECT count(*) FROM phoenix.processed_commands WHERE handler LIKE 'digests.generate_%'"
               )

      assert [[0]] =
               rows(
                 "SELECT count(*) FROM phoenix.processed_commands WHERE handler LIKE 'digests.calculate_%'"
               )

      assert [[0]] = rows("SELECT count(*) FROM public.job_outbox")
      assert length(D.digests(ScratchRepo, args["user_id"])) == 1
      assert Dawarich.Digests.Generation.run(ScratchRepo, @kind, args, opts) == :ok
      stats_count = :ets.lookup_element(counts, :stats, 2)
      digest_count = :ets.lookup_element(counts, :digests, 2)
      assert digest_count == 1
      assert stats_count == if(@kind == :monthly, do: 1, else: 12)
      assert [[1]] = rows("SELECT count(*) FROM public.job_outbox")

      assert [[1]] =
               rows(
                 "SELECT count(*) FROM phoenix.processed_commands WHERE handler LIKE 'digests.calculate_%'"
               )

      :ets.insert(counts, [{:stats, 0}, {:digests, 0}])
      fresh = sibling_period(@kind, Map.put(args, "event_id", Ecto.UUID.generate()))

      rows(
        "INSERT INTO public.stats(user_id,year,month,distance,created_at,updated_at) VALUES($1,$2,$3,0,now(),now())",
        [fresh["user_id"], fresh["year"], fresh["month"] || 3]
      )

      parent = self()

      barrier = fn ->
        send(parent, {:ready, self()})
        receive do: (:generate -> :ok)
      end

      concurrent_opts =
        opts |> Keyword.put(:before_claim, barrier) |> Keyword.put(:uuid, Ecto.UUID.generate())

      tasks =
        for _ <- 1..2 do
          Task.async(fn ->
            Dawarich.Digests.Generation.run(ScratchRepo, @kind, fresh, concurrent_opts)
          end)
        end

      for task <- tasks do
        pid = task.pid
        assert_receive {:ready, ^pid}, 5_000
      end

      for task <- tasks, do: send(task.pid, :generate)
      for task <- tasks, do: assert(Task.await(task) == :ok)
      assert :ets.lookup_element(counts, :digests, 2) == 1
      assert :ets.lookup_element(counts, :stats, 2) == if(@kind == :monthly, do: 1, else: 12)
      assert [[2]] = rows("SELECT count(*) FROM public.job_outbox")
      sibling = sibling_period(@kind, fresh)
      sibling_opts = Keyword.put(opts, :uuid, Ecto.UUID.generate())
      assert Dawarich.Digests.Generation.run(ScratchRepo, @kind, sibling, sibling_opts) == :ok
      assert [[3]] = rows("SELECT count(*) FROM public.job_outbox")
      before = :ets.lookup_element(counts, :stats, 2)
      assert Dawarich.Digests.Generation.run(ScratchRepo, @kind, sibling, sibling_opts) == :ok
      assert :ets.lookup_element(counts, :stats, 2) == before
    end
  end

  defp next_identity(:full, _event), do: {Ecto.UUID.generate(), 2025}
  defp next_identity(:yearly, event), do: {event, 2025}
  defp next_identity(_kind, event), do: {event, 2024}

  defp sibling_period(:monthly, args), do: Map.put(args, "month", args["month"] + 1)
  defp sibling_period(:yearly, args), do: Map.put(args, "year", args["year"] + 1)

  defp key(:stats), do: "command:stats.calculate_month"
  defp key(:full), do: "command:stats.full_recalculation"
  defp key(:monthly), do: "command:digests.calculate_month"
  defp key(:yearly), do: "command:digests.calculate_year"

  defp publish(kind, event, user, year, month) do
    opts = [oban: @oban, event_id: event, clock: 100, scheduled_at: ~U[2024-03-01 00:00:00Z]]

    case kind do
      :stats ->
        Schedule.calculate(ScratchRepo, user, year, month, false, opts)

      :full ->
        Dawarich.Stats.StatsFullRecalculationEffects.call(
          ScratchRepo,
          %{"user_id" => user, "source_job_id" => event, "run_at" => 100}
        )

      :monthly ->
        Dawarich.Digests.Schedule.monthly(ScratchRepo, user, year, month, "Etc/UTC", opts)

      :yearly ->
        Dawarich.Digests.Schedule.yearly(ScratchRepo, user, year, "Etc/UTC", opts)
    end
  end

  defp delivery_count do
    [[count]] =
      rows(
        "SELECT (SELECT count(*) FROM public.job_outbox) + (SELECT count(*) FROM oban.oban_jobs) + (SELECT count(*) FROM phoenix.rails_commands)"
      )

    count
  end
end

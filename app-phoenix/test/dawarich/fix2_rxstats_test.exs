defmodule Dawarich.Fix2RxStatsTest do
  use Dawarich.JobsCase
  alias Dawarich.DigestFixtures, as: D
  alias Dawarich.Digests.Generation
  alias Dawarich.Jobs.{Ownership, Processed}

  setup do
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

  for kind <- [:monthly, :yearly] do
    @kind kind
    @tag a12f3b_case: "RX04_#{kind}"
    test "#{kind} failed generation remains retryable" do
      kase = D.job_case!("new_#{@kind}_en")
      D.load!(ScratchRepo, kase)
      args = D.job_args(kase)
      opts = D.job_options(kase)
      fault = fn _ -> raise "transient digest store failure" end
      first = Generation.run(ScratchRepo, @kind, args, Keyword.put(opts, :before_store, fault))
      assert D.digests(ScratchRepo, args["user_id"]) == []
      after_failure = rows("SELECT handler FROM phoenix.processed_commands ORDER BY handler")
      second = Generation.run(ScratchRepo, @kind, args, opts)
      digests = D.digests(ScratchRepo, args["user_id"])
      assert length(digests) == 1
      assert match?({:error, %RuntimeError{}}, first)
      assert second == :ok
      assert after_failure == []

      assert [[1]] =
               rows("SELECT count(*) FROM notifications WHERE user_id=$1 AND kind=2", [
                 args["user_id"]
               ])
    end

    @tag a12f3b_case: "RX05_#{kind}"
    test "#{kind} receipt from previous release suppresses redelivery" do
      kase = D.job_case!("new_#{@kind}_en")
      D.load!(ScratchRepo, kase)
      args = D.job_args(kase)
      period = if @kind == :monthly, do: "month", else: "year"
      opts = D.job_options(kase)
      Ownership.put!(ScratchRepo, "command:mail.digest.#{@kind}", :oban)

      assert Processed.once(ScratchRepo, args["event_id"], "digests.calculate_" <> period, fn ->
               assert {:ok, _} = apply(Dawarich.Digests.Run, @kind, [ScratchRepo, args, opts])
               Dawarich.Mail.ResidualCommands.digest(ScratchRepo, period, args)
               :ok
             end) == :ok

      counter = :ets.new(:review_counter, [:public])
      :ets.insert(counter, {:stores, 0})

      replay_opts =
        Keyword.put(opts, :after_store, fn _ -> :ets.update_counter(counter, :stores, 1) end)

      assert Generation.run(ScratchRepo, @kind, args, replay_opts) == :ok
      calls = :ets.lookup_element(counter, :stores, 2)
      [[intents]] = rows("SELECT count(*) FROM public.job_outbox")
      assert calls == 0
      assert intents == 1
    end
  end

  @tag a12f3b_case: "RX06"
  test "Rails scheduled execution retains completion identity when forwarded to native" do
    assert Dawarich.Stats.EffectIdentity.id(
             "00000000-0000-4000-8000-000000000001",
             "stats.calculate_month",
             %{"user_id" => 14101, "year" => 2025, "month" => 3}
           ) == "faeefa31-e5b4-54b7-ab80-994733839961"

    start_oban(__MODULE__.Oban)

    for kind <- [:stats, :monthly, :yearly] do
      reset!(ScratchRepo)
      kase = D.job_case!("new_#{if kind == :yearly, do: :yearly, else: :monthly}_en")
      D.load!(ScratchRepo, kase)
      source = Ecto.UUID.generate()
      args = D.job_args(kase)

      type =
        case kind do
          :stats -> "stats.calculate_month"
          :monthly -> "digests.calculate_month"
          :yearly -> "digests.calculate_year"
        end

      args = if kind == :yearly, do: Map.delete(args, "month"), else: args
      receipt = Dawarich.Stats.EffectIdentity.id(source, type, args)
      Ownership.put!(ScratchRepo, "command:" <> type, :sidekiq)
      opts = [event_id: source, oban: __MODULE__.Oban]

      case kind do
        :stats ->
          Dawarich.Stats.Schedule.calculate(
            ScratchRepo,
            args["user_id"],
            args["year"],
            args["month"],
            false,
            opts
          )

        :monthly ->
          Dawarich.Digests.Schedule.monthly(
            ScratchRepo,
            args["user_id"],
            args["year"],
            args["month"],
            args["time_zone"],
            opts
          )

        :yearly ->
          Dawarich.Digests.Schedule.yearly(
            ScratchRepo,
            args["user_id"],
            args["year"],
            args["time_zone"],
            opts
          )
      end

      [[payload]] = rows("SELECT payload FROM phoenix.rails_commands")
      assert payload["source_job_id"] == receipt
      Processed.mark!(ScratchRepo, receipt, type)
      Ownership.put!(ScratchRepo, "command:" <> type, :oban)
      forwarded = args |> Map.delete("event_id") |> Map.put("execution_receipt", receipt)

      forwarded =
        if kind == :stats,
          do: forwarded |> Map.delete("time_zone") |> Map.put("notify_on_failure", false),
          else: forwarded

      worker =
        case kind do
          :stats -> Dawarich.Stats.CalculateMonthWorker
          :monthly -> Dawarich.Digests.MonthlyWorker
          :yearly -> Dawarich.Digests.YearlyWorker
        end

      assert worker.args_from_command(2, forwarded) == {:error, "unsupported_version"}

      assert worker.args_from_command(1, Map.put(forwarded, "execution_receipt", "invalid")) ==
               {:error, "invalid_payload"}

      assert {:ok, decoded} = worker.args_from_command(1, forwarded)
      job = %Oban.Job{args: Map.put(decoded, "event_id", receipt)}
      fail = fn -> flunk("already executed Rails effect entered native calculation") end

      result =
        if kind == :stats,
          do: worker.perform(job, invalidated: fail),
          else: worker.perform(job, before_claim: fail)

      assert result == :ok
      assert D.digests(ScratchRepo, args["user_id"]) == []
    end
  end

  @tag a12f3b_case: "RX07"
  test "failed checkpoints from the previous fix remain retryable after upgrade" do
    for kind <- [:monthly, :yearly] do
      reset!(ScratchRepo)
      kase = D.job_case!("new_#{kind}_en")
      D.load!(ScratchRepo, kase)
      args = D.job_args(kase)
      period = if kind == :monthly, do: "month", else: "year"
      handler = "digests.generate_" <> period
      checkpoint = Dawarich.Stats.EffectIdentity.id(args["event_id"], handler, args)
      Processed.mark!(ScratchRepo, checkpoint, handler <> ":failed")
      Processed.mark!(ScratchRepo, Generation.receipt(kind, args), "digests.calculate_" <> period)
      assert Generation.run(ScratchRepo, kind, args, D.job_options(kase)) == :ok
      assert length(D.digests(ScratchRepo, args["user_id"])) == 1

      assert [[handler <> ":mail"]] ==
               rows("SELECT handler FROM phoenix.processed_commands WHERE event_id=$1", [
                 Ecto.UUID.dump!(checkpoint)
               ])
    end
  end
end

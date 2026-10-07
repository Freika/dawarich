defmodule Dawarich.Fix3RxStatsTest do
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
    @tag a12f3b_case: "RX08_#{kind}"
    test "#{kind} ownership-flip redelivery skips Rails completion between check and claim" do
      {args, opts, type} = fixture(@kind)
      terminal = Generation.receipt(@kind, args)
      args = Map.put(args, "execution_receipt", terminal)
      Ownership.put!(ScratchRepo, "command:" <> type, :sidekiq)
      counter = :counters.new(1, [])
      parent = self()

      before_claim = fn ->
        rails_complete!(@kind, args, terminal)
        assert Processed.done?(ScratchRepo, terminal)
        assert length(D.digests(ScratchRepo, args["user_id"])) == 1
        Ownership.put!(ScratchRepo, "command:" <> type, :oban)
        send(parent, :rails_completed_before_native_generation)
      end

      opts =
        opts ++
          [before_claim: before_claim, after_store: fn _ -> :counters.add(counter, 1, 1) end]

      assert Generation.run(ScratchRepo, @kind, args, opts) == :ok
      assert_received :rails_completed_before_native_generation
      assert :counters.get(counter, 1) == 0
    end

    @tag a12f3b_case: "RX09_#{kind}"
    test "#{kind} Rails skips native generation awaiting terminal retry" do
      {args, opts, type} = fixture(@kind)
      terminal = Generation.receipt(@kind, args)
      Ownership.put!(ScratchRepo, "command:" <> type, :sidekiq)
      counter = :counters.new(1, [])

      options =
        opts ++
          [
            before_store: fn _ ->
              rails!(
                "ActiveRecord::Base.transaction do; value = ActiveRecord::Base.connection.select_value(" <>
                  "\"SELECT pg_try_advisory_xact_lock(hashtextextended('#{terminal}',0))\"); " <>
                  "raise 'native generation is not locked' if value; end"
              )
            end,
            after_store: fn _ -> :counters.add(counter, 1, 1) end,
            after_terminal: fn -> ScratchRepo.rollback(:terminal_retry) end
          ]

      assert Generation.run(ScratchRepo, @kind, args, options) == {:error, :terminal_retry}
      refute Processed.done?(ScratchRepo, terminal)
      assert length(D.digests(ScratchRepo, args["user_id"])) == 1
      digest = D.digests(ScratchRepo, args["user_id"])
      rails_complete!(@kind, args, terminal)
      assert D.digests(ScratchRepo, args["user_id"]) == digest

      assert Generation.run(
               ScratchRepo,
               @kind,
               args,
               Keyword.put(opts, :after_store, fn _ -> :counters.add(counter, 1, 1) end)
             ) == :ok

      assert :counters.get(counter, 1) == 1
      assert Processed.done?(ScratchRepo, terminal)
    end
  end

  defp fixture(kind) do
    kase = D.job_case!("new_#{kind}_en")
    D.load!(ScratchRepo, kase)
    type = "digests.calculate_" <> if(kind == :monthly, do: "month", else: "year")
    {D.job_args(kase), D.job_options(kase), type}
  end

  defp rails_complete!(kind, args, terminal, completed \\ true) do
    klass =
      if kind == :monthly,
        do: "Users::Digests::Monthly::CalculatingJob",
        else: "Users::Digests::Yearly::CalculatingJob"

    positional =
      if kind == :monthly,
        do: [args["user_id"], args["year"], args["month"]],
        else: [args["user_id"], args["year"]]

    source =
      "#{klass}.new(*#{inspect(positional)}, execution_receipt: '#{terminal}').perform_now; " <>
        "puts 'RXSTATS_COMPLETION=' + Stats::EffectReceipts.done?('#{terminal}').to_s; " <>
        "raise 'unexpected Rails regeneration' if Users::Digest.where(user_id: #{args["user_id"]}).count != 1"

    output = rails!(source)

    completion =
      output |> String.split("\n") |> Enum.find(&String.starts_with?(&1, "RXSTATS_COMPLETION="))

    assert completion == "RXSTATS_COMPLETION=#{completed}"
  end

  defp rails!(source) do
    database = ScratchRepo.config()[:database]
    redis = System.fetch_env!("PHOENIX_TEST_REDIS_URL")

    source =
      "Rails.logger = ActiveSupport::Logger.new(File::NULL); ActiveJob::Base.logger = Rails.logger; " <>
        "ActiveJob::Base.queue_adapter = :test; raise 'wrong test database' unless " <>
        "ActiveRecord::Base.connection_db_config.database == '#{database}'; " <> source

    {output, status} =
      System.cmd("bundle", ["exec", "rails", "runner", source],
        cd: Path.expand(".."),
        stderr_to_stdout: true,
        env: [{"RAILS_ENV", "test"}, {"DATABASE_NAME", database}, {"REDIS_URL", redis}]
      )

    assert status == 0, "Rails peer exit #{status}"
    output
  end
end

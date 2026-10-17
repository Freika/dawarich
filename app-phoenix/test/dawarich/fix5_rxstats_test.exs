defmodule Dawarich.Fix5RxStatsTest do
  use Dawarich.JobsCase

  alias Dawarich.DigestFixtures, as: D
  alias Dawarich.Digests.{Execution, ExecutionUpgrade, Generation}
  alias Dawarich.Jobs.{Ownership, Processed}
  alias Dawarich.Stats.EffectIdentity

  setup do
    for spec <- Dawarich.Redis.cache_child_specs(), do: start_supervised!(spec)
    :ok
  end

  for kind <- [:monthly, :yearly] do
    @kind kind
    @tag a12f3b_case: "RX32_#{kind}"
    test "RX32 #{@kind} explicit generation transaction rollback cannot publish success" do
      {args, opts} = fixture(@kind)

      broken =
        Keyword.put(opts, :before_store, fn _ -> ScratchRepo.rollback(:generation_fault) end)

      assert Generation.run(ScratchRepo, @kind, args, broken) == {:error, :generation_fault}
      assert Execution.read(ScratchRepo, @kind, args) == nil
      assert D.digests(ScratchRepo, args["user_id"]) == []
      assert mail_count() == 0
      refute Processed.done?(ScratchRepo, Generation.receipt(@kind, args))
      assert rows("SELECT count(*) FROM public.notifications WHERE kind=2") == [[1]]
      count = :counters.new(1, [])
      retry = Keyword.put(opts, :after_store, fn _ -> :counters.add(count, 1, 1) end)
      assert Generation.run(ScratchRepo, @kind, args, retry) == :ok
      assert Generation.run(ScratchRepo, @kind, args, retry) == :ok
      assert :counters.get(count, 1) == 1
      assert length(D.digests(ScratchRepo, args["user_id"])) == 1
      assert mail_count() == 1
    end

    @tag a12f3b_case: "RX33_#{kind}"
    test "RX33 #{@kind} worker crash after store before generated rolls back the result and claim" do
      {args, opts} = fixture(@kind)
      parent = self()

      barrier = fn _ ->
        send(parent, {:stored, self()})
        receive do: (:release -> :ok)
      end

      {pid, ref} =
        spawn_monitor(fn ->
          Generation.run(ScratchRepo, @kind, args, Keyword.put(opts, :after_store, barrier))
        end)

      try do
        assert_receive {:stored, ^pid}, 5000
        assert D.digests(ScratchRepo, args["user_id"]) == []
        Process.exit(pid, :kill)
        assert_receive {:DOWN, ^ref, :process, ^pid, :killed}, 5000

        assert {:ok, :ok} =
                 ScratchRepo.transaction(fn ->
                   ScratchRepo.query!("SET LOCAL statement_timeout='5s'", [], log: false)
                   Execution.lock!(ScratchRepo, @kind, args, Generation.receipt(@kind, args))
                   :ok
                 end)

        assert Execution.read(ScratchRepo, @kind, args) == nil
        assert D.digests(ScratchRepo, args["user_id"]) == []
        assert mail_count() == 0
        count = :counters.new(1, [])
        retry = Keyword.put(opts, :after_store, fn _ -> :counters.add(count, 1, 1) end)
        assert Generation.run(ScratchRepo, @kind, args, retry) == :ok
        assert Generation.run(ScratchRepo, @kind, args, retry) == :ok
        assert :counters.get(count, 1) == 1
        assert length(D.digests(ScratchRepo, args["user_id"])) == 1
        assert mail_count() == 1
      after
        if Process.alive?(pid), do: Process.exit(pid, :kill)
      end
    end

    @tag a12f3b_case: "RX34_#{kind}"
    test "RX34 #{@kind} persisted generated missing resumes with an existing user without calculation or mail" do
      {args, _opts} = fixture(@kind)
      Execution.write!(ScratchRepo, @kind, args, "generated", "missing")

      assert Generation.run(ScratchRepo, @kind, args,
               stats: fn _, _, _, _, _ -> flunk("regeneration") end
             ) == :ok

      assert Execution.read(ScratchRepo, @kind, args) == {"published", "missing"}
      assert D.digests(ScratchRepo, args["user_id"]) == []
      assert mail_count() == 0
    end
  end

  for kind <- [:monthly, :yearly], outcome <- ["mail", "missing"] do
    @kind kind
    @outcome outcome
    @tag a12f3b_case: "RX35_#{kind}_#{outcome}"
    test "RX35 #{@kind} absent period adopts legacy shared #{@outcome} marker" do
      {args, _opts} = fixture(@kind)
      handler = "digests.generate_" <> period(@kind)
      marker = EffectIdentity.id(Generation.receipt(@kind, args), handler, %{})
      Processed.mark!(ScratchRepo, marker, handler <> ":" <> @outcome)
      assert Execution.read(ScratchRepo, @kind, args) == nil

      assert Generation.run(ScratchRepo, @kind, args,
               stats: fn _, _, _, _, _ -> flunk("regeneration") end
             ) == :ok

      assert Execution.read(ScratchRepo, @kind, args) == {"published", @outcome}
      assert D.digests(ScratchRepo, args["user_id"]) == []
      assert mail_count() == if(@outcome == "mail", do: 1, else: 0)
    end
  end

  for kind <- [:monthly, :yearly], first <- [:native, :rails] do
    @kind kind
    @first first
    @tag a12f3b_case: "RX36_#{kind}_#{first}"
    test "RX36 #{@kind} historical missing checkpoint upgrades #{@first}-first from retained arguments" do
      {args, opts} = fixture(@kind)
      rows("UPDATE public.users SET deleted_at=now() WHERE id=$1", [args["user_id"]])

      rows("INSERT INTO oban.oban_jobs(queue,worker,args) VALUES('digests','legacy.digest',$1)", [
        args
      ])

      assert Dawarich.LegacyDigestGeneration.run(
               ScratchRepo,
               @kind,
               args,
               Keyword.put(opts, :after_terminal, fn ->
                 ScratchRepo.rollback(:legacy_publication_fault)
               end)
             ) == {:error, :legacy_publication_fault}

      handler = "digests.generate_" <> period(@kind)
      old = EffectIdentity.id(args["event_id"], handler, args)

      assert rows("SELECT handler FROM phoenix.processed_commands WHERE event_id=$1", [
               Ecto.UUID.dump!(old)
             ]) == [[handler <> ":missing"]]

      rows("UPDATE public.users SET deleted_at=NULL WHERE id=$1", [args["user_id"]])
      assert Execution.read(ScratchRepo, @kind, args) == nil
      assert ExecutionUpgrade.backfill(ScratchRepo) == :ok
      assert Execution.read(ScratchRepo, @kind, args) == {"generated", "missing"}
      opts = Keyword.put(opts, :stats, fn _, _, _, _, _ -> flunk("regeneration") end)

      if @first == :rails do
        rails_missing_replay(@kind, args)
        assert Generation.run(ScratchRepo, @kind, args, opts) == :ok
      else
        assert Generation.run(ScratchRepo, @kind, args, opts) == :ok
        rails_missing_replay(@kind, args)
      end

      assert Execution.read(ScratchRepo, @kind, args) == {"published", "missing"}
      assert D.digests(ScratchRepo, args["user_id"]) == []
      assert mail_count() == 0
    end
  end

  defp fixture(kind) do
    kase = D.job_case!("new_#{kind}_en")
    D.load!(ScratchRepo, kase)
    Ownership.put!(ScratchRepo, "command:mail.digest." <> Atom.to_string(kind), :sidekiq)
    {D.job_args(kase), D.job_options(kase)}
  end

  defp period(kind), do: if(kind == :monthly, do: "month", else: "year")

  defp mail_count,
    do:
      rows("SELECT count(*) FROM phoenix.rails_commands WHERE kind LIKE 'digests.email_%'")
      |> hd()
      |> hd()

  defp rails_missing_replay(kind, args) do
    Ownership.put!(ScratchRepo, "command:digests.calculate_" <> period(kind), :sidekiq)

    klass =
      if kind == :monthly,
        do: "Users::Digests::Monthly::CalculatingJob",
        else: "Users::Digests::Yearly::CalculatingJob"

    positional =
      if kind == :monthly,
        do: [args["user_id"], args["year"], args["month"]],
        else: [args["user_id"], args["year"]]

    source =
      "Rails.logger=ActiveSupport::Logger.new(File::NULL); ActiveJob::Base.logger=Rails.logger; ActiveJob::Base.queue_adapter=:test; " <>
        "$calls=0; Stats::CalculateMonth.prepend(Module.new do; def call; $calls+=1; super; end; end); " <>
        "#{klass}.new(*#{inspect(positional)}, execution_receipt: '#{Generation.receipt(kind, args)}').perform_now; " <>
        "raise 'regeneration' unless $calls==0; raise 'mail admission' unless ActiveJob::Base.queue_adapter.enqueued_jobs.empty?"

    {_, status} =
      System.cmd("bundle", ["exec", "rails", "runner", source],
        cd: Path.expand(".."),
        stderr_to_stdout: true,
        env: [
          {"RAILS_ENV", "test"},
          {"DATABASE_NAME", ScratchRepo.config()[:database]},
          {"REDIS_URL", System.fetch_env!("PHOENIX_TEST_REDIS_URL")}
        ]
      )

    assert status == 0, "Rails peer exit #{status}"
  end
end

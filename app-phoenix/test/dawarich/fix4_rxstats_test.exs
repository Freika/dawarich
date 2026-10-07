defmodule Dawarich.Fix4RxStatsTest do
  use Dawarich.JobsCase

  alias Dawarich.DigestFixtures, as: D
  alias Dawarich.Digests.Generation
  alias Dawarich.Jobs.{Ownership, Processed}
  alias Dawarich.Stats.EffectIdentity

  setup do
    for spec <- Dawarich.Redis.cache_child_specs(), do: start_supervised!(spec)
    :ok
  end

  for kind <- [:monthly, :yearly], state <- ["absent", "claimed", "generated", "published"] do
    @kind kind
    @state state
    @tag a12f3b_case: "RX10_#{kind}_#{state}"
    test "RX10 #{@kind} native resumes #{@state} from the single period record" do
      {args, opts} = fixture(@kind)
      seed_state(args, @kind, @state)
      count = :counters.new(1, [])
      opts = Keyword.put(opts, :after_store, fn _ -> :counters.add(count, 1, 1) end)
      assert Generation.run(ScratchRepo, @kind, args, opts) == :ok

      assert Generation.run(
               ScratchRepo,
               @kind,
               Map.put(args, "event_id", Ecto.UUID.generate()),
               opts
             ) == :ok

      assert :counters.get(count, 1) == if(@state in ["absent", "claimed"], do: 1, else: 0)
      assert state(args, @kind) == "published"
      assert mail_count() == if(@state == "published", do: 0, else: 1)
    end
  end

  for kind <- [:monthly, :yearly] do
    @kind kind
    @tag a12f3b_case: "RX11_#{kind}"
    test "RX11 #{@kind} failed generation releases the period claim" do
      {args, opts} = fixture(@kind)
      key = if @kind == :monthly, do: :monthly, else: :yearly
      broken = Keyword.put(opts, key, fn _, _, _ -> raise "generation fault" end)

      broken =
        if @kind == :monthly,
          do: Keyword.put(opts, key, fn _, _, _, _ -> raise "generation fault" end),
          else: broken

      assert {:error, _} = Generation.run(ScratchRepo, @kind, args, broken)
      assert state(args, @kind) == nil
      assert D.digests(ScratchRepo, args["user_id"]) == []
      assert Generation.run(ScratchRepo, @kind, args, opts) == :ok
      assert state(args, @kind) == "published"
    end

    @tag a12f3b_case: "RX12_#{kind}"
    test "RX12 #{@kind} publication rollback retries publication across runtimes only" do
      {args, opts} = fixture(@kind)
      count = :counters.new(1, [])
      opts = Keyword.put(opts, :after_store, fn _ -> :counters.add(count, 1, 1) end)

      assert Generation.run(
               ScratchRepo,
               @kind,
               args,
               Keyword.put(opts, :after_terminal, fn ->
                 ScratchRepo.rollback(:publication_fault)
               end)
             ) == {:error, :publication_fault}

      assert state(args, @kind) == "generated"
      assert mail_count() == 0
      assert rails_replay(@kind, args) == 0
      assert state(args, @kind) == "published"
      assert Generation.run(ScratchRepo, @kind, args, opts) == :ok
      assert :counters.get(count, 1) == 1
      assert mail_count() == 1
    end

    @tag a12f3b_case: "RX13_#{kind}"
    test "RX13 #{@kind} missing user commits a no-mail period outcome" do
      {args, opts} = fixture(@kind)
      args = Map.put(args, "user_id", 2_100_000_000)
      assert Generation.run(ScratchRepo, @kind, args, opts) == :ok
      assert state(args, @kind) == "published"
      assert mail_count() == 0
    end
  end

  for kind <- [:monthly, :yearly], first <- [:rails, :native] do
    @kind kind
    @first first
    @tag a12f3b_case: "RX14_#{kind}_#{first}"
    test "RX14 #{@kind} pre-fix3 successful checkpoint upgrades #{@first}-first without regeneration" do
      {args, opts} = fixture(@kind)
      period = period(@kind)
      handler = "digests.generate_" <> period
      checkpoint = EffectIdentity.id(args["event_id"], handler, args)

      assert Dawarich.LegacyDigestGeneration.run(
               ScratchRepo,
               @kind,
               args,
               Keyword.put(opts, :after_terminal, fn ->
                 ScratchRepo.rollback(:legacy_publication_fault)
               end)
             ) == {:error, :legacy_publication_fault}

      assert Processed.done?(ScratchRepo, checkpoint)
      refute Processed.done?(ScratchRepo, Generation.receipt(@kind, args))
      upgrade!()
      count = :counters.new(1, [])
      opts = Keyword.put(opts, :after_store, fn _ -> :counters.add(count, 1, 1) end)

      if @first == :rails do
        assert rails_replay(@kind, args) == 0
        assert Generation.run(ScratchRepo, @kind, args, opts) == :ok
      else
        assert Generation.run(ScratchRepo, @kind, args, opts) == :ok
        assert rails_replay(@kind, args) == 0
      end

      assert :counters.get(count, 1) == 0
      assert length(D.digests(ScratchRepo, args["user_id"])) == 1
      assert mail_count() == 1
      assert state(args, @kind) == "published"
    end
  end

  for kind <- [:monthly, :yearly] do
    @kind kind
    @tag a12f3b_case: "RX18_#{kind}"
    test "RX18 #{@kind} native publishes Rails-generated period after Rails publication failure" do
      {args, opts} = fixture(@kind)
      assert rails_replay(@kind, args, true) == if(@kind == :monthly, do: 1, else: 12)
      assert state(args, @kind) == "generated"
      assert mail_count() == 0
      count = :counters.new(1, [])

      assert Generation.run(
               ScratchRepo,
               @kind,
               args,
               Keyword.put(opts, :after_store, fn _ -> :counters.add(count, 1, 1) end)
             ) == :ok

      assert :counters.get(count, 1) == 0
      assert state(args, @kind) == "published"
      assert mail_count() == 1
    end
  end

  for kind <- [:monthly, :yearly], first <- [:rails, :native] do
    @kind kind
    @first first
    @tag a12f3b_case: "RX24_#{kind}_#{first}"
    test "RX24 #{@kind} legacy no-data generation upgrades #{@first}-first from retained accepted args" do
      kase = D.job_case!("no_data_#{@kind}_en")
      D.load!(ScratchRepo, kase)
      args = D.job_args(kase)
      opts = D.job_options(kase)
      Ownership.put!(ScratchRepo, "command:mail.digest." <> Atom.to_string(@kind), :sidekiq)

      ScratchRepo.query!(
        "INSERT INTO oban.oban_jobs(queue,worker,args) VALUES('digests','legacy.digest',$1)",
        [args],
        log: false
      )

      assert Dawarich.LegacyDigestGeneration.run(
               ScratchRepo,
               @kind,
               args,
               Keyword.put(opts, :after_terminal, fn ->
                 ScratchRepo.rollback(:legacy_publication_fault)
               end)
             ) == {:error, :legacy_publication_fault}

      assert D.digests(ScratchRepo, args["user_id"]) == []
      upgrade!()
      assert state(args, @kind) == "generated"
      count = :counters.new(1, [])

      opts =
        Keyword.put(opts, :stats, fn repo, user, year, month, options ->
          :counters.add(count, 1, 1)
          Dawarich.Stats.CalculateMonth.call(repo, user, year, month, options)
        end)

      if @first == :rails do
        assert rails_replay(@kind, args) == 0
        assert Generation.run(ScratchRepo, @kind, args, opts) == :ok
      else
        assert Generation.run(ScratchRepo, @kind, args, opts) == :ok
        assert rails_replay(@kind, args) == 0
      end

      assert :counters.get(count, 1) == 0
      assert mail_count() == 1
      assert state(args, @kind) == "published"
    end
  end

  for kind <- [:monthly, :yearly] do
    @kind kind
    @tag a12f3b_case: "RX25_#{kind}"
    test "RX25 #{@kind} upgrade imports already admitted legacy mail as published" do
      {args, opts} = fixture(@kind)
      assert Dawarich.LegacyDigestGeneration.run(ScratchRepo, @kind, args, opts) == :ok
      assert mail_count() == 1
      upgrade!()
      assert state(args, @kind) == "published"
      assert rails_replay(@kind, args) == 0
      assert Generation.run(ScratchRepo, @kind, args, opts) == :ok
      assert mail_count() == 1
    end
  end

  for kind <- [:monthly, :yearly], first <- [:rails, :native] do
    @kind kind
    @first first
    @tag a12f3b_case: "RX27_#{kind}_#{first}"
    test "RX27 #{@kind} failed legacy checkpoint upgrades #{@first}-first without false completion" do
      {args, opts} = fixture(@kind)
      handler = "digests.generate_" <> period(@kind)
      old = EffectIdentity.id(args["event_id"], handler, args)
      Processed.mark!(ScratchRepo, old, handler <> ":failed")

      Processed.mark!(
        ScratchRepo,
        Generation.receipt(@kind, args),
        "digests.calculate_" <> period(@kind)
      )

      ScratchRepo.query!(
        "INSERT INTO oban.oban_jobs(queue,worker,args) VALUES('digests','legacy.digest',$1)",
        [args],
        log: false
      )

      upgrade!()
      assert state(args, @kind) == nil
      count = :counters.new(1, [])
      opts = Keyword.put(opts, :after_store, fn _ -> :counters.add(count, 1, 1) end)

      if @first == :rails do
        assert rails_replay(@kind, args) == if(@kind == :monthly, do: 1, else: 12)
        assert Generation.run(ScratchRepo, @kind, args, opts) == :ok
        assert :counters.get(count, 1) == 0
      else
        assert Generation.run(ScratchRepo, @kind, args, opts) == :ok
        assert state(args, @kind) == "published"
        assert rails_replay(@kind, args) == 0
        assert :counters.get(count, 1) == 1
      end

      assert state(args, @kind) == "published"
      assert length(D.digests(ScratchRepo, args["user_id"])) == 1
      assert mail_count() == 1
    end
  end

  defp fixture(kind) do
    kase = D.job_case!("new_#{kind}_en")
    D.load!(ScratchRepo, kase)
    Ownership.put!(ScratchRepo, "command:mail.digest." <> Atom.to_string(kind), :sidekiq)
    {D.job_args(kase), D.job_options(kase)}
  end

  defp seed_state(_args, _kind, "absent"), do: :ok

  defp seed_state(args, kind, value) do
    if table?() do
      ScratchRepo.query!(
        "INSERT INTO phoenix.digest_executions(effect,user_id,year,month,state,outcome) VALUES($1,$2,$3,$4,$5,'mail')",
        [
          "digests.calculate_" <> period(kind),
          args["user_id"],
          args["year"],
          args["month"] || 0,
          value
        ],
        log: false
      )

      if value == "published" do
        ScratchRepo.query!(
          "UPDATE phoenix.digest_executions SET legacy=true WHERE effect=$1 AND user_id=$2 AND year=$3 AND month=$4",
          [
            "digests.calculate_" <> period(kind),
            args["user_id"],
            args["year"],
            args["month"] || 0
          ],
          log: false
        )

        handler = "digests.generate_" <> period(kind)

        Processed.mark!(
          ScratchRepo,
          EffectIdentity.id(args["event_id"], handler, args),
          handler <> ":mail"
        )
      end
    end
  end

  defp state(args, kind) do
    if table?() do
      case ScratchRepo.query!(
             "SELECT state FROM phoenix.digest_executions WHERE effect=$1 AND user_id=$2 AND year=$3 AND month=$4",
             [
               "digests.calculate_" <> period(kind),
               args["user_id"],
               args["year"],
               args["month"] || 0
             ],
             log: false
           ).rows do
        [[value]] -> value
        [] -> nil
      end
    end
  end

  defp table?,
    do:
      ScratchRepo.query!("SELECT to_regclass('phoenix.digest_executions') IS NOT NULL", [],
        log: false
      ).rows == [[true]]

  defp period(kind), do: if(kind == :monthly, do: "month", else: "year")

  defp mail_count,
    do:
      Process.get(:rails_mail_count, 0) +
        hd(
          hd(
            ScratchRepo.query!(
              "SELECT count(*) FROM phoenix.rails_commands WHERE kind IN ('digests.email_month','digests.email_year')",
              [],
              log: false
            ).rows
          )
        )

  defp upgrade! do
    path = "priv/repo/sql/20261007180000_digest_executions_backfill.sql"
    if File.exists?(path), do: ScratchRepo.query!(File.read!(path), [], log: false)

    if Code.ensure_loaded?(Dawarich.Digests.ExecutionUpgrade),
      do: apply(Dawarich.Digests.ExecutionUpgrade, :backfill, [ScratchRepo])
  end

  defp rails_replay(kind, args, publication_fault \\ false) do
    period = period(kind)
    Ownership.put!(ScratchRepo, "command:digests.calculate_" <> period, :sidekiq)
    database = ScratchRepo.config()[:database]

    klass =
      if kind == :monthly,
        do: "Users::Digests::Monthly::CalculatingJob",
        else: "Users::Digests::Yearly::CalculatingJob"

    positional =
      if kind == :monthly,
        do: [args["user_id"], args["year"], args["month"]],
        else: [args["user_id"], args["year"]]

    fault =
      if publication_fault,
        do:
          "Users::Digests::Commands.singleton_class.prepend(Module.new do; def publish_email(*args, **opts); raise IOError, 'publication fault'; end; end); ",
        else: ""

    source =
      "Rails.logger = ActiveSupport::Logger.new(File::NULL); ActiveJob::Base.logger = Rails.logger; ActiveJob::Base.queue_adapter = :test; " <>
        fault <>
        "$calls=0; Stats::CalculateMonth.prepend(Module.new do; def call; $calls+=1; super; end; end); " <>
        "#{klass}.new(*#{inspect(positional)}, execution_receipt: '#{Generation.receipt(kind, args)}').perform_now; puts 'RX14_MAIL=' + ActiveJob::Base.queue_adapter.enqueued_jobs.count { |job| job[:job].name.include?('EmailSendingJob') }.to_s; puts 'RX14_CALLS=' + $calls.to_s"

    {output, status} =
      System.cmd("bundle", ["exec", "rails", "runner", source],
        cd: Path.expand(".."),
        stderr_to_stdout: true,
        env: [
          {"RAILS_ENV", "test"},
          {"DATABASE_NAME", database},
          {"REDIS_URL", System.fetch_env!("PHOENIX_TEST_REDIS_URL")}
        ]
      )

    assert status == 0, "Rails peer exit #{status}"
    mail = Enum.find(String.split(output, "\n"), &String.starts_with?(&1, "RX14_MAIL="))

    Process.put(
      :rails_mail_count,
      String.to_integer(String.replace_prefix(mail, "RX14_MAIL=", ""))
    )

    line = Enum.find(String.split(output, "\n"), &String.starts_with?(&1, "RX14_CALLS="))
    assert line
    line |> String.replace_prefix("RX14_CALLS=", "") |> String.to_integer()
  end
end

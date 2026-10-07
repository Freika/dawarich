defmodule Dawarich.Jobs.OwnershipTest do
  use Dawarich.JobsCase, async: true, group: :scratch_db

  alias Dawarich.Jobs.{Claimer, Dispatch, Ownership, Registry}

  @key "command:test.echo"

  test "a missing row means sidekiq" do
    assert Ownership.with_owner(ScratchRepo, @key, :sidekiq, fn -> :ran end) == {:ok, :ran}
    assert Ownership.with_owner(ScratchRepo, @key, :oban, fn -> :ran end) == {:skip, :sidekiq}
  end

  test "runs only for the owning runtime" do
    :ok = Ownership.put!(ScratchRepo, @key, :oban)

    assert Ownership.with_owner(ScratchRepo, @key, :oban, fn -> :ran end) == {:ok, :ran}
    assert Ownership.with_owner(ScratchRepo, @key, :sidekiq, fn -> :ran end) == {:skip, :oban}
  end

  test "a raise inside the gate rolls the effect back and propagates" do
    :ok = Ownership.put!(ScratchRepo, @key, :oban)

    assert_raise RuntimeError, "boom", fn ->
      Ownership.with_owner(ScratchRepo, @key, :oban, fn ->
        rows(
          "INSERT INTO phoenix.runtime_nodes (node, started_at, beat_at) VALUES ('probe', now(), now())"
        )

        raise "boom"
      end)
    end

    assert rows("SELECT count(*) FROM phoenix.runtime_nodes") == [[0]]
  end

  test "put! records pinning and who changed it" do
    :ok = Ownership.put!(ScratchRepo, @key, :sidekiq, pinned: true, by: "test")

    assert rows("SELECT owner, pinned, updated_by FROM phoenix.job_owners WHERE key = $1", [@key]) ==
             [["sidekiq", true, "test"]]
  end

  test "an owner change waits for a gate that holds the row, and the next gate sees the new owner" do
    :ok = Ownership.put!(ScratchRepo, @key, :oban)
    parent = self()

    holder =
      Task.async(fn ->
        Ownership.with_owner(ScratchRepo, @key, :oban, fn ->
          send(parent, :holding)

          receive do
            :release -> :effect_done
          end
        end)
      end)

    assert_receive :holding

    error =
      assert_raise Postgrex.Error, fn ->
        ScratchRepo.transaction(fn ->
          ScratchRepo.query!("SET LOCAL lock_timeout = '50ms'")

          ScratchRepo.query!("UPDATE phoenix.job_owners SET owner = 'sidekiq' WHERE key = $1", [
            @key
          ])
        end)
      end

    assert error.postgres.code == :lock_not_available

    send(holder.pid, :release)
    assert Task.await(holder) == {:ok, :effect_done}

    {:ok, _} =
      ScratchRepo.transaction(fn ->
        ScratchRepo.query!("UPDATE phoenix.job_owners SET owner = 'sidekiq' WHERE key = $1", [
          @key
        ])
      end)

    assert Ownership.with_owner(ScratchRepo, @key, :oban, fn -> :late end) == {:skip, :sidekiq}
  end

  test "Cloud owner flip cannot cross an accepted source effect or split joint keys" do
    keys = Ownership.joint_keys("cron:lite_archival_warning_job")
    key = hd(keys)
    oban = __MODULE__.CloudOban
    start_oban(oban)
    entry = Enum.find(Registry.entries(), &(&1.key == key))

    source =
      source_port(
        ~s|
      JobOwnership.with_owner('#{key}') do
        puts 'CLOUD:HOLDING'
        raise 'source channel closed' unless STDIN.gets
        ActiveRecord::Base.connection.execute("INSERT INTO phoenix.runtime_nodes (node, started_at, beat_at) VALUES ('source', now(), now())")
      end
    |,
        :ownership
      )

    try do
      assert source_line(source) == "CLOUD:HOLDING"
      assert Claimer.claim(ScratchRepo, oban, entry, "50ms") == {:error, :lock_not_available}
      assert rows("SELECT count(*) FROM phoenix.runtime_nodes") == [[0]]
    after
      Port.command(source, "release\n")
      assert source_exit(source) == 0
    end

    assert Claimer.claim(ScratchRepo, oban, entry) == :claimed

    assert rows("SELECT key, owner FROM phoenix.job_owners ORDER BY key") ==
             Enum.map(keys, &[&1, "oban"])

    holder =
      Dawarich.LockRace.hold(fn ->
        assert Ownership.with_owner(ScratchRepo, key, :oban, fn -> :held end) == {:ok, :held}
      end)

    try do
      assert source_run(
               ~s|
        JobOwnership.send(:remove_const, :LOCK_TIMEOUT)
        JobOwnership.const_set(:LOCK_TIMEOUT, '50ms')
        begin
          JobOwnership.release!('#{key}', by: 'cloud-test')
          puts 'CLOUD:CHANGED'
        rescue ActiveRecord::LockWaitTimeout
          puts 'CLOUD:BLOCKED'
        end
      |,
               :ownership
             ) == "CLOUD:BLOCKED"

      assert rows("SELECT owner FROM phoenix.job_owners ORDER BY key") == [["oban"], ["oban"]]
    after
      Dawarich.LockRace.commit(holder)
    end

    assert source_run(
             ~s|puts "CLOUD:\#{JobOwnership.with_owner('#{key}') { :effect }}"|,
             :ownership
           ) ==
             "CLOUD:not_owner"

    assert Ownership.with_owner(ScratchRepo, key, :oban, fn -> :native_effect end) ==
             {:ok, :native_effect}

    rows("UPDATE phoenix.job_owners SET owner = 'sidekiq' WHERE key = $1", [key])

    for joint <- keys, runtime <- [:sidekiq, :oban] do
      assert Ownership.with_owner(ScratchRepo, joint, runtime, fn -> :split_effect end) ==
               {:skip, :inconsistent}
    end
  end

  test "Cloud delayed source replay and native replay use one carried event identity" do
    fixture = trip_fixture!()
    id = fixture["trip"]["id"]
    root = "00000000-0000-4000-8000-000000003306"
    due = ~U[2026-06-01 12:00:00.000000Z]
    :ok = Ownership.put!(ScratchRepo, "command:trips.calculate", :oban)
    event = source_run(~s|
      Time.use_zone('Pacific/Chatham') do
        I18n.with_locale(:de) do
          2.times { Trips::CalculateAllJob.forward(#{id}, 'mi', '#{root}') }
          puts "CLOUD:\#{JobOutbox.sole.event_id}"
        end
      end
    |) |> String.replace_prefix("CLOUD:", "")
    rows("UPDATE job_outbox SET scheduled_at = $1", [due])
    oban = __MODULE__.ReplayOban
    start_oban(oban)
    assert Dispatch.run(repo: ScratchRepo, oban: oban, now: DateTime.add(due, -1)) == %{}
    assert Dispatch.run(repo: ScratchRepo, oban: oban, now: due) == %{dispatched: 1}
    assert [[args]] = rows("SELECT args FROM oban.oban_jobs")
    assert args["event_id"] == event
    assert rows("SELECT scheduled_at FROM job_outbox") == [[due]]
    job = %Oban.Job{args: args, attempt: 1, max_attempts: 3}
    assert Dawarich.Trips.CalculateWorker.perform(job) == :ok
    assert Dawarich.Trips.CalculateWorker.perform(job) == :ok
    assert_trip_effect(fixture, event)
    unresolved = Ecto.UUID.generate()

    assert Dawarich.Jobs.Processed.once(ScratchRepo, unresolved, "cloud-probe", fn ->
             {:skip, :sidekiq}
           end) ==
             {:error, {:skip, :sidekiq}}

    refute Dawarich.Jobs.Processed.done?(ScratchRepo, unresolved)
    :ok = stop_supervised(oban)
    start_oban(oban)
    assert source_run(~s|
      Trips::CalculateAllJob.forward(#{id}, 'mi', '#{root}')
      puts "CLOUD:\#{JobOutbox.count}"
    |) == "CLOUD:1"
    assert Dispatch.run(repo: ScratchRepo, oban: oban, now: due) == %{}
    assert_trip_effect(fixture, event)
  end

  test "accepted source trip continues through the native owner without a new source child" do
    fixture = trip_fixture!()
    id = fixture["trip"]["id"]
    root = "00000000-0000-4000-8000-000000003307"
    :ok = Ownership.put!(ScratchRepo, "command:trips.calculate", :sidekiq)

    event =
      source_run(~s"""
        before = Sidekiq::Queue.new('trips').map(&:jid)
        job = Trips::CalculateAllJob.new(#{id}, 'mi')
        job.job_id = '#{root}'
        job.scheduled_at = Time.utc(2026, 6, 1, 12)

        accepted = job.serialize.merge('locale' => 'de', 'timezone' => 'Pacific/Chatham')
        ActiveJob::Base.execute(accepted)
        children = Sidekiq::Queue.new('trips').reject { |child| before.include?(child.jid) }
        raise 'materialized children missing' unless children.size == 3
        begin
          raise 'carried child root changed' unless children.all? { |child| child.args.first['arguments'].last == '#{root}' }
          JobOwnership.put!(Trips::CalculateAllJob::OWNER_KEY, :oban, pinned: false, by: 'cloud-test')
          ENV['DAWARICH_CLOUD_DRAIN_ONLY'] = 'true'
          2.times { ActiveJob::Base.execute(accepted) }
          children.each { |child| ActiveJob::Base.execute(child.args.first) }
        ensure
          children.each(&:delete)
          children.map { |child| child.args.first['arguments'].last }.uniq.each { |token| Rails.cache.delete(Trips::CalculateAllJob.pending_key(#{id}, token)) }
        end
        row = JobOutbox.sole
        raise 'due time changed' unless row.scheduled_at == job.scheduled_at
        raise 'source children appeared' unless Sidekiq::Queue.new('trips').map(&:jid).sort == before.sort
        raise 'wrapper context changed' unless accepted.values_at('locale', 'timezone') == ['de', 'Pacific/Chatham']
        puts "CLOUD:\#{row.event_id}"
      """)
      |> String.replace_prefix("CLOUD:", "")

    oban = __MODULE__.TripOban
    start_oban(oban)

    assert Dispatch.run(repo: ScratchRepo, oban: oban, now: ~U[2026-06-01 12:00:00Z]) == %{
             dispatched: 1
           }

    assert [[args]] = rows("SELECT args FROM oban.oban_jobs")
    assert args["event_id"] == event
    job = %Oban.Job{args: args, attempt: 1, max_attempts: 3}
    assert Dawarich.Trips.CalculateWorker.perform(job) == :ok
    assert source_run(~s|
      before = Sidekiq::Queue.new('trips').size
      job = Trips::CalculateAllJob.new(#{id}, 'mi')
      job.job_id = '#{root}'
      job.perform_now
      Trips::CalculatePathJob.perform_now(#{id}, '#{root}')
      Trips::CalculateDistanceJob.perform_now(#{id}, 'mi', '#{root}')
      Trips::CalculateCountriesJob.perform_now(#{id}, 'mi', '#{root}')
      raise 'source children appeared' unless Sidekiq::Queue.new('trips').size == before
      puts "CLOUD:\#{JobOutbox.count}"
    |) == "CLOUD:1"
    assert Dawarich.Trips.CalculateWorker.perform(job) == :ok
    assert_trip_effect(fixture, event)
  end

  test "unsupported accepted source chain stays retained and blocks the Cloud switch" do
    trip_fixture!()
    assert source_run(~s|
      require 'sidekiq/api'
      job = Trips::CalculateAllJob.new(990101, 'mi')
      accepted = job.serialize
      jid = Sidekiq::Client.push('class' => 'ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper',
                                 'wrapped' => job.class.name, 'queue' => 'trips', 'args' => [accepted])
      before = Sidekiq::Queue.new('trips').size
      ENV['DAWARICH_CLOUD_DRAIN_ONLY'] = 'true'
      begin
        ActiveJob::Base.execute(accepted)
        puts 'CLOUD:ACKNOWLEDGED'
      rescue JobOwnership::UnsupportedSourceChain
        raise 'owner changed' unless JobOwnership.with_owner(Trips::CalculateAllJob::OWNER_KEY) { :retained } == :retained
        raise 'children appeared' unless Sidekiq::Queue.new('trips').size == before
        raise 'success receipt appeared' unless ActiveRecord::Base.connection.select_value('SELECT count(*) FROM phoenix.processed_commands').zero?
        raise 'forward appeared' unless JobOutbox.count.zero?
        raise 'original was lost' unless Sidekiq::Queue.new('trips').find_job(jid).args == [accepted]
        puts 'CLOUD:RETAINED'
      ensure
        Sidekiq::Queue.new('trips').find_job(jid)&.delete
      end
    |) == "CLOUD:RETAINED"
    assert rows("SELECT owner FROM phoenix.job_owners") == [["sidekiq"]]
  end

  test "actual native trip transaction blocks source release and same-root distance" do
    fixture = trip_fixture!()
    id = fixture["trip"]["id"]
    :ok = Ownership.put!(ScratchRepo, "command:trips.calculate", :oban)

    source =
      source_port(
        ~s|
      puts 'CLOUD:READY'
      raise 'source channel closed' unless STDIN.gets
      JobOwnership.send(:remove_const, :LOCK_TIMEOUT)
      JobOwnership.const_set(:LOCK_TIMEOUT, '50ms')
      begin
        JobOwnership.release!('command:trips.calculate', by: 'leaf-race')
        puts 'CLOUD:RELEASED'
      rescue ActiveRecord::LockWaitTimeout
        puts 'CLOUD:BLOCKED'
      end
    |,
        :rails
      )

    assert source_line(source) == "CLOUD:READY"
    event = source_run(~s|
      Trips::CalculateAllJob.forward(#{id}, 'mi', '00000000-0000-4000-8000-000000003383')
      puts "CLOUD:\#{JobOutbox.sole.event_id}"
    |) |> String.replace_prefix("CLOUD:", "")

    holder =
      Dawarich.LockRace.hold(fn ->
        rows("SELECT id FROM trips WHERE id = $1 FOR UPDATE", [id])
      end)

    worker = Task.async(fn -> native_trip(id, event) end)

    try do
      assert Dawarich.LockRace.settle(worker, "SELECT started_at, ended_at%") == :blocked
      Port.command(source, "release\n")
      assert source_line(source) == "CLOUD:BLOCKED"
      assert source_exit(source) == 0
    after
      Dawarich.LockRace.commit(holder)
      assert Task.await(worker) == :ok
    end

    assert source_run(~s|
      accepted = Trips::CalculateDistanceJob.new(#{id}, 'mi', '00000000-0000-4000-8000-000000003383').serialize
      JobOwnership.release!('command:trips.calculate', by: 'leaf-race')
      broadcasts = 0
      callback = ->(*) { broadcasts += 1 }
      ActiveSupport::Notifications.subscribed(callback, 'broadcast.action_cable') do
        ActiveJob::Base.execute(accepted)
      end
      puts "CLOUD:\#{broadcasts}"
    |) == "CLOUD:0"
    assert_trip_effect(fixture, event)
  end

  test "completed source root redelivery creates no additional native effects" do
    fixture = trip_fixture!()
    id = fixture["trip"]["id"]
    event = source_chain(id, "00000000-0000-4000-8000-000000003382", 3)
    assert native_trip(id, event) == :ok
    assert rows("SELECT kind FROM phoenix.trip_events") == []
    assert Dawarich.Jobs.Processed.done?(ScratchRepo, event)
  end

  test "partially completed source root resumes only unfinished native effects" do
    fixture = trip_fixture!()
    id = fixture["trip"]["id"]
    event = source_chain(id, "00000000-0000-4000-8000-000000003384", 1)
    assert native_trip(id, event) == :ok
    assert native_trip(id, event) == :ok

    assert rows("SELECT kind FROM phoenix.trip_events ORDER BY id") ==
             [["path"], ["countries"], ["finished"]]

    assert Dawarich.Jobs.Processed.done?(ScratchRepo, event)
  end

  test "materialized child first preserves accepted parent due time" do
    fixture = trip_fixture!()
    id = fixture["trip"]["id"]
    event = source_chain(id, "00000000-0000-4000-8000-000000003381", 0)

    assert rows("SELECT scheduled_at FROM job_outbox WHERE event_id = $1", [
             Ecto.UUID.dump!(event)
           ]) ==
             [[~U[2026-06-01 12:00:00.000000Z]]]
  end

  test "accepted native replay waits for terminal source root completion after pinning" do
    fixture = trip_fixture!()
    id = fixture["trip"]["id"]
    root = "00000000-0000-4000-8000-000000003385"
    :ok = Ownership.put!(ScratchRepo, "command:trips.calculate", :sidekiq, pinned: true)

    source =
      source_port(
        ~s|
      puts "CLOUD:\#{Trips::CalculationReceipts.event_id(#{id}, '#{root}')}"
      raise 'source channel closed' unless STDIN.gets
      Rails.cache.write(Trips::CalculateAllJob.pending_key(#{id}, '#{root}'), 3, raw: true)
      Trips::CalculatePathJob.perform_now(#{id}, '#{root}')
      Trips::CalculateDistanceJob.perform_now(#{id}, 'mi', '#{root}')
      held = false
      callback = ->(*) { unless held; held = true; puts 'CLOUD:HOLDING'; raise 'source channel closed' unless STDIN.gets; end }
      ActiveSupport::Notifications.subscribed(callback, 'broadcast.action_cable') do
        Trips::CalculateCountriesJob.perform_now(#{id}, 'mi', '#{root}')
      end
    |,
        :rails
      )

    event = source_line(source) |> String.replace_prefix("CLOUD:", "")
    Port.command(source, "execute\n")
    assert source_line(source) == "CLOUD:HOLDING"
    worker = Dawarich.LockRace.attempt(fn -> native_trip(id, event) end)

    try do
      assert Dawarich.LockRace.settle(worker, "SELECT pg_advisory_xact_lock%") == :blocked
    after
      Port.command(source, "release\n")
      assert source_exit(source) == 0
      send(self(), {:native_result, Task.await(worker)})
    end

    assert_receive {:native_result, {:ok, :ok}}
    assert rows("SELECT kind FROM phoenix.trip_events") == []
    assert Dawarich.Jobs.Processed.done?(ScratchRepo, event)
  end

  test "rollback pins every registry key including joint keys to Sidekiq across restart" do
    keys = Registry.entries() |> Enum.map(& &1.key) |> Enum.uniq() |> Enum.sort()

    rows(
      "INSERT INTO phoenix.job_owners(key, owner) SELECT key, 'oban' FROM unnest($1::text[]) AS key",
      [keys]
    )

    joint = Ownership.joint_keys("cron:lite_archival_warning_job") |> Enum.sort()

    holder =
      Dawarich.LockRace.hold(fn ->
        rows("SELECT key FROM phoenix.job_owners WHERE key = $1 FOR SHARE", [List.last(joint)])
      end)

    try do
      assert source_run(
               ~s|
        JobOwnership.send(:remove_const, :LOCK_TIMEOUT)
        JobOwnership.const_set(:LOCK_TIMEOUT, '50ms')
        begin
          JobOwnership.release!('#{hd(joint)}', by: 'rollback')
          puts 'CLOUD:CHANGED'
        rescue ActiveRecord::LockWaitTimeout
          puts 'CLOUD:BLOCKED'
        end
      |,
               :ownership
             ) == "CLOUD:BLOCKED"

      assert rows("SELECT owner, pinned FROM phoenix.job_owners WHERE key = ANY($1)", [joint]) ==
               [["oban", false], ["oban", false]]
    after
      Dawarich.LockRace.commit(holder)
    end

    assert source_run(
             ~s"""
               JSON.parse('#{Jason.encode!(keys)}').each { |key| JobOwnership.release!(key, by: 'rollback') }
               puts 'CLOUD:PINNED'
             """,
             :ownership
           ) == "CLOUD:PINNED"

    expected = Enum.map(keys, &[&1, "sidekiq", true])
    assert rows("SELECT key, owner, pinned FROM phoenix.job_owners ORDER BY key") == expected

    oban = __MODULE__.RollbackOban

    for _ <- 1..2 do
      start_oban(oban)

      assert Claimer.claim_all(ScratchRepo, oban, Registry.entries())
             |> Enum.all?(fn {_key, result} -> result == :pinned end)

      assert rows("SELECT key, owner, pinned FROM phoenix.job_owners ORDER BY key") == expected
      assert rows("SELECT count(*) FROM oban.oban_jobs") == [[0]]
      :ok = stop_supervised(oban)
    end

    assert Dawarich.Jobs.Drain.status(ScratchRepo).binary_rollback == "OBSERVED_EMPTY"

    rows(
      "INSERT INTO phoenix.job_owners(key, owner, pinned) VALUES ('command:unknown.rollback', 'sidekiq', true)"
    )

    assert "unknown_owners" in Dawarich.Jobs.Drain.status(ScratchRepo).binary_reasons
    rows("DELETE FROM phoenix.job_owners WHERE key = 'command:unknown.rollback'")

    rows(
      "INSERT INTO phoenix.runtime_nodes(node, started_at, beat_at) VALUES ('stale-rollback', now(), now() - interval '2 minutes')"
    )

    status = Dawarich.Jobs.Drain.status(ScratchRepo)
    assert status.binary_rollback == "BLOCKED"
    assert "heartbeat_invalid" in status.binary_reasons
    assert status.certainty == "UNKNOWN"
  end

  defp native_trip(id, event) do
    Dawarich.Trips.CalculateWorker.perform(%Oban.Job{
      args: %{"trip_id" => id, "distance_unit" => "mi", "event_id" => event},
      attempt: 1,
      max_attempts: 3
    })
  end

  defp source_chain(id, root, completed) do
    source_run(~s"""
      job = Trips::CalculateAllJob.new(#{id}, 'mi')
      job.job_id = '#{root}'
      job.scheduled_at = Time.utc(2026, 6, 1, 12)
      accepted = job.serialize
      before = Sidekiq::Queue.new('trips').map(&:jid)
      ActiveJob::Base.execute(accepted)
      children = Sidekiq::Queue.new('trips').reject { |child| before.include?(child.jid) }
      children.sort_by! { |child| child.args.first['job_class'] == 'Trips::CalculateDistanceJob' ? 0 : 1 }
      begin
        broadcasts = 0
        callback = ->(*) { broadcasts += 1 }
        ActiveSupport::Notifications.subscribed(callback, 'broadcast.action_cable') do
          children.first(#{completed}).each { |child| ActiveJob::Base.execute(child.args.first) }
        end
        raise 'source effects missing' unless broadcasts == (#{completed} == 3 ? 4 : #{completed})
        JobOwnership.put!('command:trips.calculate', :oban, pinned: false, by: 'replay')
        ENV['DAWARICH_CLOUD_DRAIN_ONLY'] = 'true'
        children.drop(#{completed}).each { |child| ActiveJob::Base.execute(child.args.first) }
        ActiveJob::Base.execute(accepted)
        puts "CLOUD:\#{JobOutbox.sole.event_id}"
      ensure
        children.each(&:delete)
        Rails.cache.delete(Trips::CalculateAllJob.pending_key(#{id}, '#{root}'))
      end
    """)
    |> String.replace_prefix("CLOUD:", "")
  end

  defp trip_fixture! do
    fixture =
      Path.expand("../../fixtures/trips/calculation.json", __DIR__)
      |> File.read!()
      |> Jason.decode!()

    rows(
      "INSERT INTO users (id, email, settings, created_at, updated_at) SELECT id, email, settings, created_at, updated_at FROM json_populate_record(NULL::users, $1)",
      [fixture["user"]]
    )

    for {table, records} <- [
          {"point_sources", fixture["point_sources"]},
          {"points", fixture["points"]}
        ],
        record <- records do
      rows("INSERT INTO #{table} SELECT * FROM json_populate_record(NULL::#{table}, $1)", [record])
    end

    rows(
      "INSERT INTO trips (id, user_id, name, started_at, ended_at, created_at, updated_at) SELECT id, user_id, name, started_at, ended_at, created_at, updated_at FROM json_populate_record(NULL::trips, $1)",
      [fixture["trip"]]
    )

    fixture
  end

  defp assert_trip_effect(fixture, event) do
    expected = fixture["expected"]

    assert rows(
             "SELECT encode(ST_AsEWKB(path), 'hex'), distance, visited_countries, last_recalculated_at FROM trips WHERE id = $1",
             [fixture["trip"]["id"]]
           ) ==
             [[expected["path_ewkb"], expected["distance"], expected["visited_countries"], nil]]

    assert rows("SELECT kind, distance_unit, failed FROM phoenix.trip_events ORDER BY id") ==
             [
               ["path", "mi", false],
               ["distance", "mi", false],
               ["countries", "mi", false],
               ["finished", "mi", false]
             ]

    assert Dawarich.Jobs.Processed.done?(ScratchRepo, event)
  end

  defp source_port(code, boot) do
    database =
      System.fetch_env!("PHOENIX_TEST_DATABASE") <>
        System.get_env("MIX_TEST_PARTITION", "") <> "_scratch"

    unless database == ScratchRepo.config()[:database],
      do: raise("allocated private test DB required")

    redis = Application.fetch_env!(:dawarich, :redis)[:url]

    preload =
      if boot == :ownership do
        "require 'rails'; require 'active_record'; Rails.logger = Logger.new(File::NULL); " <>
          "ActiveRecord::Base.establish_connection(adapter: 'postgresql', database: ENV.fetch('DATABASE_NAME'), host: '127.0.0.1', port: ENV.fetch('DATABASE_PORT'), username: ENV.fetch('DATABASE_USERNAME'), password: ENV.fetch('DATABASE_PASSWORD')); require './app/services/job_ownership'; "
      else
        "require './config/environment'; require 'sidekiq/api'; "
      end

    script =
      "STDOUT.sync = true; " <>
        preload <>
        "puts 'CLOUD:BOOTED'; exit 1 unless STDIN.gets; begin; " <>
        code <>
        "; rescue => e; puts 'CLOUD:ERROR:' + (['due time changed', 'source children appeared', 'children appeared', 'owner changed', 'success receipt appeared', 'forward appeared', 'wrapper context changed', 'materialized children missing', 'carried child root changed', 'source effects missing'].include?(e.message) ? e.message : e.class.name); exit 1; end"

    port =
      Port.open({:spawn_executable, System.find_executable("asdf")}, [
        :binary,
        :exit_status,
        :use_stdio,
        :stderr_to_stdout,
        {:line, 16384},
        {:cd, Application.fetch_env!(:dawarich, :rails_root)},
        {:args, ["exec", "bundle", "exec", "ruby", "-e", script]},
        {:env,
         Enum.map(
           [
             {"RAILS_ENV", "test"},
             {"DATABASE_NAME", database},
             {"DATABASE_HOST", "127.0.0.1"},
             {"REDIS_URL", redis},
             {"SELF_HOSTED", "false"},
             {"DAWARICH_CLOUD_DRAIN_ONLY", "false"}
           ],
           fn {key, value} -> {String.to_charlist(key), String.to_charlist(value)} end
         )}
      ])

    source_ready(port)
    Port.command(port, "execute\n")
    port
  end

  defp source_ready(port) do
    receive do
      {^port, {:data, {:eol, "CLOUD:BOOTED"}}} -> :ok
      {^port, {:data, _}} -> source_ready(port)
      {^port, {:exit_status, status}} -> flunk("source boot exited: #{status}")
    end
  end

  defp source_run(code, boot \\ :rails) do
    port = source_port(code, boot)

    try do
      result = source_line(port)
      assert source_exit(port) == 0, result
      result
    after
      if Port.info(port), do: Port.close(port)
    end
  end

  defp source_line(port) do
    receive do
      {^port, {:data, {:eol, "CLOUD:" <> _ = line}}} -> line
      {^port, {:data, _}} -> source_line(port)
      {^port, {:exit_status, status}} -> flunk("source exited before barrier: #{status}")
    after
      5_000 -> flunk("source did not reach barrier")
    end
  end

  defp source_exit(port) do
    receive do
      {^port, {:exit_status, status}} -> status
      {^port, {:data, _}} -> source_exit(port)
    after
      5_000 -> flunk("source did not exit")
    end
  end
end

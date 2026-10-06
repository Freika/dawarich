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
        STDIN.gets
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
    :ok = Ownership.put!(ScratchRepo, "command:trips.calculate", :oban)
    event = source_run(~s|
      before = Sidekiq::Queue.new('trips').size
      job = Trips::CalculateAllJob.new(#{id}, 'mi')
      job.job_id = '#{root}'
      job.scheduled_at = Time.utc(2026, 6, 1, 12)

      accepted = job.serialize.merge('locale' => 'de', 'timezone' => 'Pacific/Chatham')
      2.times { ActiveJob::Base.execute(accepted) }
      row = JobOutbox.sole
      raise 'due time changed' unless row.scheduled_at == job.scheduled_at
      raise 'source children appeared' unless Sidekiq::Queue.new('trips').size == before
      raise 'wrapper context changed' unless accepted.values_at('locale', 'timezone') == ['de', 'Pacific/Chatham']
      puts "CLOUD:\#{row.event_id}"
    |) |> String.replace_prefix("CLOUD:", "")
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

    assert rows("SELECT event_id::text FROM phoenix.processed_commands") == [[event]]
  end

  defp source_port(code, boot) do
    database = ScratchRepo.config()[:database]

    unless String.starts_with?(database, "dawarich_phoenix_test"),
      do: raise("private test DB required")

    redis = Application.fetch_env!(:dawarich, :redis)[:url]

    preload =
      if boot == :ownership do
        "require 'rails'; require 'active_record'; Rails.logger = Logger.new(File::NULL); " <>
          "ActiveRecord::Base.establish_connection(adapter: 'postgresql', database: ENV.fetch('DATABASE_NAME'), host: '127.0.0.1', port: ENV.fetch('DATABASE_PORT'), username: ENV.fetch('DATABASE_USERNAME'), password: ENV.fetch('DATABASE_PASSWORD')); require './app/services/job_ownership'; "
      else
        "require './config/environment'; require 'sidekiq/api'; "
      end

    script =
      preload <>
        "STDOUT.sync = true; begin; " <>
        code <>
        "; rescue => e; puts 'CLOUD:ERROR:' + (['due time changed', 'source children appeared', 'children appeared', 'owner changed', 'success receipt appeared', 'forward appeared', 'wrapper context changed'].include?(e.message) ? e.message : e.class.name); exit 1; end"

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
  end

  defp source_run(code, boot \\ :rails) do
    port = source_port(code, boot)
    result = source_line(port)
    assert source_exit(port) == 0, result
    result
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

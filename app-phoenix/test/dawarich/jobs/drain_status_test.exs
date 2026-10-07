defmodule Dawarich.Jobs.DrainStatusTest do
  use Dawarich.JobsCase

  alias Dawarich.Jobs.{Drain, Housekeeping, Registry}

  @oban __MODULE__.Oban
  @now ~U[2026-10-05 10:00:00Z]

  @tag a12f3b_case: "E21a"
  test "all-native drain remains blocked by future pending outbox reverse leases quarantine and dead commands" do
    start_oban(@oban)
    keys = Enum.map(Registry.entries(), & &1.key)

    rows(
      "INSERT INTO phoenix.job_owners (key, owner) SELECT key, 'oban' FROM unnest($1::text[]) AS key",
      [keys]
    )

    rows(
      "INSERT INTO phoenix.runtime_nodes (node, started_at, beat_at) VALUES ('drain-native', now(), now())"
    )

    future =
      outbox!(
        command_type: "trips.calculate",
        scheduled_at: DateTime.add(DateTime.utc_now(), 3600)
      )

    quarantined = outbox!(command_type: "trips.calculate")

    rows(
      "UPDATE job_outbox SET state = 'quarantined', error_code = 'unsupported_version' WHERE event_id = $1",
      [Ecto.UUID.dump!(quarantined)]
    )

    rows("""
    INSERT INTO phoenix.rails_commands (kind, available_at, attempts, leased_until) VALUES
    ('cache.preheat_user', now() + interval '1 hour', 0, NULL),
    ('cache.preheat_user', now(), 0, NULL),
    ('cache.preheat_user', now(), 1, now() + interval '1 hour'),
    ('cache.preheat_user', now(), 3, NULL)
    """)

    rows("""
    INSERT INTO phoenix.rails_commands_dead (id, kind, payload, attempts, last_error, created_at)
    VALUES (990001, 'cache.preheat_user', '{}', 25, 'synthetic-private-error', now())
    """)

    rows(
      "INSERT INTO phoenix.release_operations (id, command_type, cursor) VALUES (gen_random_uuid(), 'release.route_opacity', '{}')"
    )

    for worker <- [
          Dawarich.Imports.Trek.ScheduleWorker,
          Dawarich.Imports.Teslamate.ScheduleWorker
        ] do
      Oban.insert!(@oban, worker.new(%{}, scheduled_at: DateTime.add(DateTime.utc_now(), 3600)))
    end

    status = Drain.status(ScratchRepo)
    assert status.forward == "BLOCKED"
    assert status.binary_rollback == "BLOCKED"
    assert status.counts.pending_outbox == 1
    assert status.counts.future_outbox == 1
    assert status.counts.quarantined == 1
    assert status.counts.reverse_pending == 4
    assert status.counts.reverse_future == 1
    assert status.counts.reverse_due == 2
    assert status.counts.reverse_leased == 1
    assert status.counts.reverse_retrying == 1
    assert status.counts.reverse_dead == 1
    assert status.counts.release_pending == 1
    assert status.counts.incomplete_oban == 2
    assert Enum.all?(status.legacy_schedulers, &(&1.incomplete == 1))
    assert "legacy_schedulers" in status.forward_reasons
    assert "legacy_schedulers" in status.binary_reasons
    assert "pending_outbox" in status.forward_reasons
    assert "residual_producers" in status.forward_reasons
    assert Enum.all?(status.producer_kinds, &(&1.status == "BLOCKED"))
    assert Enum.any?(status.producer_kinds, &(&1.kind == "cache.preheat_sweep"))
    refute Jason.encode!(status) =~ "synthetic-private-error"

    rows("DELETE FROM job_outbox WHERE event_id = $1", [Ecto.UUID.dump!(future)])
    rows("DELETE FROM phoenix.job_owners WHERE key = $1", [hd(keys)])
    rows("UPDATE phoenix.job_owners SET owner = 'sidekiq' WHERE key = $1", [List.last(keys)])
    status = Drain.status(ScratchRepo)
    assert status.counts.missing_owners == 1
    assert status.counts.mixed_owners == 1
    assert status.counts.pending_outbox == 0
    rows("DELETE FROM phoenix.runtime_nodes")
    assert "heartbeat_invalid" in Drain.status(ScratchRepo).forward_reasons
  end

  test "Cloud shutdown observation blocks all unresolved native and reverse debt" do
    start_oban(@oban)
    native_owners!()

    rows(
      "INSERT INTO phoenix.runtime_nodes (node, started_at, beat_at) VALUES ('shutdown', now(), now())"
    )

    vectors = [
      {"INSERT INTO job_outbox (event_id, command_type, command_version, payload, scheduled_at) VALUES (gen_random_uuid(), 'trips.calculate', 1, '{}', now())",
       "DELETE FROM job_outbox", "pending_outbox"},
      {"INSERT INTO job_outbox (event_id, command_type, command_version, payload, scheduled_at) VALUES (gen_random_uuid(), 'trips.calculate', 1, '{}', now() + interval '1 hour')",
       "DELETE FROM job_outbox", "pending_outbox"},
      {"INSERT INTO job_outbox (event_id, command_type, command_version, payload, state, scheduled_at) VALUES (gen_random_uuid(), 'trips.calculate', 1, '{}', 'quarantined', now())",
       "DELETE FROM job_outbox", "quarantined"},
      {"INSERT INTO phoenix.rails_commands(kind) VALUES ('synthetic.unknown')",
       "DELETE FROM phoenix.rails_commands", "reverse_pending"},
      {"INSERT INTO phoenix.rails_commands(kind, available_at) VALUES ('synthetic.unknown', now() + interval '1 hour')",
       "DELETE FROM phoenix.rails_commands", "reverse_pending"},
      {"INSERT INTO phoenix.rails_commands(kind, leased_until) VALUES ('synthetic.unknown', now() + interval '1 hour')",
       "DELETE FROM phoenix.rails_commands", "reverse_pending"},
      {"INSERT INTO phoenix.rails_commands(kind, attempts) VALUES ('synthetic.unknown', 2)",
       "DELETE FROM phoenix.rails_commands", "reverse_pending"},
      {"INSERT INTO phoenix.rails_commands_dead(id, kind, payload, attempts, last_error, created_at) VALUES (990003, 'synthetic.unknown', '{}', 25, 'synthetic-private-error', now())",
       "DELETE FROM phoenix.rails_commands_dead", "reverse_dead"},
      {"INSERT INTO phoenix.release_operations(id, command_type, cursor) VALUES (gen_random_uuid(), 'release.time_anchor', '{}')",
       "DELETE FROM phoenix.release_operations", "release_pending"},
      {"INSERT INTO phoenix.track_generations(id, user_id, mode, untracked_only, low_priority, status, total_chunks) VALUES (gen_random_uuid(), 7, 'bulk', false, false, 'running', 1)",
       "DELETE FROM phoenix.track_generations", "unfinished_generations"},
      {"WITH g AS (INSERT INTO phoenix.track_generations(id, user_id, mode, untracked_only, low_priority, status, total_chunks, completed_chunks) VALUES (gen_random_uuid(), 7, 'bulk', false, false, 'completed', 1, 1) RETURNING id) INSERT INTO phoenix.track_generation_chunks(generation_id, chunk_id, start_ts, end_ts, buffer_start_ts, buffer_end_ts) SELECT id, 0, 0, 1, 0, 1 FROM g",
       "DELETE FROM phoenix.track_generations", "unfinished_generations"},
      {"DELETE FROM phoenix.job_owners WHERE key = 'command:trips.calculate'",
       "INSERT INTO phoenix.job_owners(key, owner) VALUES ('command:trips.calculate', 'oban')",
       "missing_owners"},
      {"INSERT INTO phoenix.job_owners(key) VALUES ('command:synthetic.unknown')",
       "DELETE FROM phoenix.job_owners WHERE key = 'command:synthetic.unknown'",
       "unknown_owners"},
      {"UPDATE phoenix.runtime_nodes SET beat_at = now() - interval '2 minutes'",
       "UPDATE phoenix.runtime_nodes SET beat_at = now()", "heartbeat_invalid"}
    ]

    for {insert, cleanup, reason} <- vectors do
      rows(insert)
      status = Drain.status(ScratchRepo)
      assert status.shutdown == "BLOCKED"
      assert reason in status.shutdown_reasons
      refute Jason.encode!(status) =~ "synthetic-private-error"
      rows(cleanup)
      refute reason in Drain.status(ScratchRepo).shutdown_reasons
    end

    Oban.insert!(@oban, Dawarich.ReleaseOperations.RouteOpacity.new(%{"version" => 1}))
    assert "incomplete_oban" in Drain.status(ScratchRepo).shutdown_reasons
  end

  test "Cloud native drain unreadable tables never becomes an empty observation" do
    for table <-
          ~w(job_outbox phoenix.job_owners phoenix.rails_commands phoenix.rails_commands_dead phoenix.track_generations phoenix.track_generation_chunks phoenix.release_operations phoenix.runtime_nodes oban.oban_jobs) do
      rows("ALTER TABLE #{table} RENAME TO drain_unreadable")

      try do
        status = Drain.status(ScratchRepo)
        assert status.certainty == "UNKNOWN"
        assert status.shutdown == "BLOCKED"
        assert status.forward == "BLOCKED"
        assert status.binary_rollback == "BLOCKED"
        assert status.shutdown_reasons == ["database_unreadable"]
        refute Map.has_key?(status, :counts)
      after
        [schema, name] =
          if String.contains?(table, "."), do: String.split(table, "."), else: ["public", table]

        rows("ALTER TABLE #{schema}.drain_unreadable RENAME TO #{name}")
      end
    end
  end

  test "rollback rejects accepted native work and unfinished release operations after pinning" do
    start_oban(@oban)
    pin_owners!()
    assert Drain.status(ScratchRepo).binary_rollback == "OBSERVED_EMPTY"

    for state <- ~w(available scheduled retryable executing discarded suspended) do
      job = Oban.insert!(@oban, Dawarich.ReleaseOperations.RouteOpacity.new(%{"version" => 1}))

      rows(
        "UPDATE oban.oban_jobs SET state = $2::oban.oban_job_state, scheduled_at = now() + interval '1 hour' WHERE id = $1",
        [job.id, state]
      )

      status = Drain.status(ScratchRepo)
      assert status.binary_rollback == "BLOCKED"
      assert "incomplete_oban" in status.binary_reasons
      rows("DELETE FROM oban.oban_jobs WHERE id = $1", [job.id])
    end

    for state <- ~w(running failed) do
      rows(
        "INSERT INTO phoenix.release_operations(id, command_type, cursor, status, error) VALUES (gen_random_uuid(), 'release.time_anchor', '{}', $1, 'synthetic-private-error')",
        [state]
      )

      assert "release_pending" in Drain.status(ScratchRepo).binary_reasons
      refute Jason.encode!(Drain.status(ScratchRepo)) =~ "synthetic-private-error"
      rows("DELETE FROM phoenix.release_operations")
    end

    for state <- ~w(pending quarantined) do
      event =
        outbox!(
          command_type: "synthetic.unknown",
          scheduled_at: DateTime.add(DateTime.utc_now(), 3600)
        )

      rows("UPDATE job_outbox SET state = $2 WHERE event_id = $1", [Ecto.UUID.dump!(event), state])

      assert Drain.status(ScratchRepo).binary_rollback == "BLOCKED"
      rows("DELETE FROM job_outbox WHERE event_id = $1", [Ecto.UUID.dump!(event)])
    end

    rows(
      "INSERT INTO phoenix.rails_commands_dead(id, kind, payload, attempts, last_error, created_at) VALUES (990004, 'synthetic.unknown', '{}', 25, 'synthetic-private-error', now())"
    )

    assert "reverse_dead" in Drain.status(ScratchRepo).binary_reasons
    rows("DELETE FROM phoenix.rails_commands_dead")

    rows(
      "INSERT INTO phoenix.runtime_nodes(node, started_at, beat_at) VALUES ('rollback-stale', now(), now() - interval '2 minutes')"
    )

    assert "heartbeat_invalid" in Drain.status(ScratchRepo).binary_reasons
  end

  @tag h04_case: "H04b"
  test "rollback drains pending and accepted native work after pinning without a Sidekiq transfer" do
    :ok = Supervisor.terminate_child(Dawarich.Supervisor, Oban)
    start_oban(Oban)
    on_exit(fn -> Supervisor.restart_child(Dawarich.Supervisor, Oban) end)
    native_owners!()
    fixture = rollback_trip!()
    trip_id = fixture["trip"]["id"]
    event = Ecto.UUID.generate()

    accepted =
      Oban.insert!(
        Dawarich.Trips.CalculateWorker.new(%{
          "trip_id" => trip_id,
          "distance_unit" => "mi",
          "event_id" => event
        })
      )

    track = Dawarich.Wave6Fixtures.track!(fixture["user"]["id"])

    for offset <- [0, 60],
        do:
          Dawarich.Wave6Fixtures.point!(fixture["user"]["id"], %{
            "track_id" => track,
            "timestamp" => 1_577_836_800 + offset
          })

    segment = Dawarich.Wave6Fixtures.segment!(track, %{"start_index" => 0, "end_index" => 1})
    due = ~U[2026-10-07 12:00:00.000000Z]

    pending =
      outbox!(command_type: "release.time_anchor", payload: %{"from_id" => 0}, scheduled_at: due)

    {:ok, redis} = Redix.start_link(Application.fetch_env!(:dawarich, :redis)[:url])

    source_before =
      Redix.command!(redis, ["KEYS", "queue:*"])
      |> Map.new(fn key -> {key, Redix.command!(redis, ["LRANGE", key, 0, -1])} end)

    try do
      pin_owners!()

      assert Dawarich.Jobs.Ownership.with_owner(
               ScratchRepo,
               "command:trips.calculate",
               :oban,
               fn -> flunk("new root admitted") end
             ) == {:skip, :sidekiq}

      assert Dawarich.Families.InvitationCleanupWorker.perform(%Oban.Job{}) ==
               {:cancel, :not_owner}

      assert Dawarich.Jobs.Dispatch.run(repo: ScratchRepo, oban: Oban, now: DateTime.add(due, -1)) ==
               %{}

      assert "pending_outbox" in Drain.status(ScratchRepo).binary_reasons
      assert %{success: 1, failure: 0} = Oban.drain_queue(queue: :trips)
      assert Dawarich.Jobs.Processed.done?(ScratchRepo, event)

      assert rows("SELECT kind FROM phoenix.trip_events ORDER BY id") == [
               ["path"],
               ["distance"],
               ["countries"],
               ["finished"]
             ]

      assert Dawarich.Trips.CalculateWorker.perform(accepted) == :ok
      assert rows("SELECT count(*) FROM phoenix.trip_events") == [[4]]

      assert Dawarich.Jobs.Dispatch.run(repo: ScratchRepo, oban: Oban, now: due) == %{
               dispatched: 1
             }

      assert rows("SELECT scheduled_at FROM job_outbox WHERE event_id = $1", [
               Ecto.UUID.dump!(pending)
             ]) == [[due]]

      assert %{success: 1, failure: 0} = Oban.drain_queue(queue: :maintenance, with_limit: 1)

      assert [[%{"operation_id" => ^pending} = successor]] =
               rows("SELECT args FROM oban.oban_jobs WHERE args ? 'operation_id'")

      assert successor["cursor"]["from_id"] == segment
      assert "release_pending" in Drain.status(ScratchRepo).binary_reasons

      assert %{success: 1, failure: 0} =
               Oban.drain_queue(queue: :maintenance, with_scheduled: DateTime.utc_now())

      assert rows("SELECT status FROM phoenix.release_operations WHERE id = $1", [
               Ecto.UUID.dump!(pending)
             ]) == [["completed"]]

      assert rows(
               "SELECT extract(epoch FROM start_at)::bigint, extract(epoch FROM end_at)::bigint FROM track_segments WHERE id = $1",
               [segment]
             ) == [[1_577_836_800, 1_577_836_860]]

      status = Drain.status(ScratchRepo)
      assert status.binary_rollback == "OBSERVED_EMPTY"
      assert status.scope == "native_sql"
      assert status.g49 == "BLOCKED"

      assert status.source == %{
               status: "NOT_OBSERVED",
               certainty: "UNKNOWN",
               reasons: ["source_inspection_required"]
             }

      assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]

      source_after =
        Redix.command!(redis, ["KEYS", "queue:*"])
        |> Map.new(fn key -> {key, Redix.command!(redis, ["LRANGE", key, 0, -1])} end)

      assert source_after == source_before

      rows(
        "INSERT INTO phoenix.runtime_nodes(node, started_at, beat_at) VALUES ('rollback-drainer', now(), now() - interval '2 minutes')"
      )

      assert Drain.status(ScratchRepo).binary_rollback == "BLOCKED"
      assert "heartbeat_invalid" in Drain.status(ScratchRepo).binary_reasons
    after
      GenServer.stop(redis)
    end
  end

  defp rollback_trip! do
    fixture =
      Path.expand("../../fixtures/trips/calculation.json", __DIR__)
      |> File.read!()
      |> Jason.decode!()

    rows(
      "INSERT INTO users (id, email, settings, created_at, updated_at) SELECT id, email, settings, created_at, updated_at FROM json_populate_record(NULL::users, $1)",
      [fixture["user"]]
    )

    rows(
      "INSERT INTO trips (id, user_id, name, started_at, ended_at, created_at, updated_at) SELECT id, user_id, name, started_at, ended_at, created_at, updated_at FROM json_populate_record(NULL::trips, $1)",
      [fixture["trip"]]
    )

    for {table, records} <- [
          {"point_sources", fixture["point_sources"]},
          {"points", fixture["points"]}
        ],
        record <- records do
      rows("INSERT INTO #{table} SELECT * FROM json_populate_record(NULL::#{table}, $1)", [record])
    end

    fixture
  end

  defp pin_owners! do
    for entry <- Registry.entries(),
        do: Dawarich.Jobs.Ownership.put!(ScratchRepo, entry.key, :sidekiq, pinned: true)
  end

  defp native_owners! do
    keys = Enum.map(Registry.entries(), & &1.key)

    rows(
      "INSERT INTO phoenix.job_owners(key, owner) SELECT key, 'oban' FROM unnest($1::text[]) AS key",
      [keys]
    )
  end

  @tag a12f3b_case: "E20a"
  test "housekeeping retains aged dead debt and drain status remains blocked" do
    rows("""
    INSERT INTO phoenix.rails_commands_dead (id, kind, payload, attempts, last_error, created_at, died_at)
    VALUES (990002, 'cache.preheat_user', '{}', 25, 'synthetic-private-error', '2025-01-01', '2025-01-01')
    """)

    Housekeeping.run!(ScratchRepo, @now)
    assert rows("SELECT id FROM phoenix.rails_commands_dead") == [[990_002]]
    assert Drain.status(ScratchRepo).counts.reverse_dead == 1
    assert "reverse_dead" in Drain.status(ScratchRepo).forward_reasons

    for {class, index} <-
          Enum.with_index(
            ~w(ActionMailer::MailDeliveryJob ActionMailer::DeliveryJob ActiveStorage::AnalyzeJob ActiveStorage::PurgeJob ActiveStorage::MirrorJob ActiveStorage::TransformJob Unknown::RetiredJob),
            1
          ) do
      payload = %{
        "job_class" => class,
        "arguments" => [
          %{"_aj_globalid" => "gid://dawarich/User/42"},
          %{"_aj_symbol_keys" => ["unknown"]}
        ],
        "version" => 99
      }

      rows(
        "INSERT INTO phoenix.rails_commands_dead(id,kind,payload,attempts,last_error,created_at) VALUES($1,$2,$3,25,'synthetic-private-error',now())",
        [990_002 + index, class, payload]
      )
    end

    before = rows("SELECT id,kind,payload FROM phoenix.rails_commands_dead ORDER BY id")
    Housekeeping.run!(ScratchRepo, @now)
    assert rows("SELECT id,kind,payload FROM phoenix.rails_commands_dead ORDER BY id") == before
    status = Drain.status(ScratchRepo)
    assert status.counts.reverse_dead == 8
    assert status.forward == "BLOCKED"
    assert status.binary_rollback == "BLOCKED"
    refute Jason.encode!(status) =~ "gid://"
    assert Drain.status(nil).forward == "BLOCKED"
    assert Drain.status(nil).binary_rollback == "BLOCKED"
    assert Drain.status(nil).forward_reasons == ["database_unreadable"]
  end

  @tag a12f3b_case: "E21b"
  test "housekeeping preserves stale unfinished generations and chunks" do
    start_oban(@oban)

    rows("""
    WITH gen AS (
      INSERT INTO phoenix.track_generations (id, user_id, mode, untracked_only, low_priority, status, total_chunks, updated_at)
      VALUES (gen_random_uuid(), 7, 'bulk', false, false, 'running', 1, '2025-01-01'),
             (gen_random_uuid(), 8, 'bulk', false, false, 'failed', 1, '2025-01-01') RETURNING id
    )
    INSERT INTO phoenix.track_generation_chunks (generation_id, chunk_id, start_ts, end_ts, buffer_start_ts, buffer_end_ts)
    SELECT id, 0, 0, 1, 0, 1 FROM gen
    """)

    Housekeeping.run!(ScratchRepo, @now)

    assert rows("SELECT status FROM phoenix.track_generations ORDER BY user_id") == [
             ["running"],
             ["failed"]
           ]

    assert rows("SELECT count(*) FROM phoenix.track_generation_chunks") == [[2]]
    assert Drain.status(ScratchRepo).counts.unfinished_generations == 2

    keys = Enum.map(Registry.entries(), & &1.key)

    rows(
      "INSERT INTO phoenix.job_owners(key,owner,pinned) SELECT key,'sidekiq',true FROM unnest($1::text[]) AS key",
      [keys]
    )

    for state <- ~w(available scheduled retryable executing suspended discarded) do
      job =
        Oban.insert!(@oban, Dawarich.Users.RecalculateWorker.new(%{"synthetic_state" => state}))

      rows("UPDATE oban.oban_jobs SET state=$2::oban.oban_job_state WHERE id=$1", [job.id, state])
    end

    status = Drain.status(ScratchRepo)
    assert status.counts.unpinned_rollback_owners == 0
    assert status.counts.incomplete_oban == 6
    assert "unfinished_generations" in status.binary_reasons
    assert "incomplete_oban" in status.binary_reasons
    rows("UPDATE phoenix.track_generations SET status='completed',completed_chunks=total_chunks")
    rows("UPDATE phoenix.track_generation_chunks SET status='completed'")
    assert Drain.status(ScratchRepo).binary_rollback == "BLOCKED"
    rows("UPDATE oban.oban_jobs SET state='completed'")
    assert Drain.status(ScratchRepo).binary_rollback == "OBSERVED_EMPTY"
    rows("UPDATE phoenix.job_owners SET pinned=false WHERE key=$1", [hd(keys)])
    assert "unpinned_rollback_owners" in Drain.status(ScratchRepo).binary_reasons
    assert Drain.status(ScratchRepo).forward == "BLOCKED"
  end
end

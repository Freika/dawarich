defmodule Dawarich.Jobs.DrainStatusTest do
  use Dawarich.JobsCase

  alias Dawarich.Jobs.{Drain, Housekeeping, Registry}

  @oban __MODULE__.Oban
  @now ~U[2026-10-05 10:00:00Z]

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

  test "housekeeping retains aged dead debt and drain status remains blocked" do
    rows("""
    INSERT INTO phoenix.rails_commands_dead (id, kind, payload, attempts, last_error, created_at, died_at)
    VALUES (990002, 'cache.preheat_user', '{}', 25, 'synthetic-private-error', '2025-01-01', '2025-01-01')
    """)

    Housekeeping.run!(ScratchRepo, @now)
    assert rows("SELECT id FROM phoenix.rails_commands_dead") == [[990_002]]
    assert Drain.status(ScratchRepo).counts.reverse_dead == 1
    assert "reverse_dead" in Drain.status(ScratchRepo).forward_reasons
  end

  test "housekeeping preserves stale unfinished generations and chunks" do
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
  end
end

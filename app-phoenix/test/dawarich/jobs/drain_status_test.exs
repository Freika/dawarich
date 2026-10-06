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

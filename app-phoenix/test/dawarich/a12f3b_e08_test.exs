defmodule Dawarich.A12f3bE08Test do
  use Dawarich.JobsCase

  alias Dawarich.Cache.{PreheatSweepWorker, PreheatUserWorker}
  alias Dawarich.DigestFixtures, as: F
  alias Dawarich.Jobs.{Drain, Ownership, Processed}
  alias Dawarich.Redis

  setup do
    for spec <- Redis.cache_child_specs(), do: start_supervised!(spec)
    {:ok, _} = Redis.cache_command(["FLUSHDB"])
    F.load!(ScratchRepo, F.case!("berlin_yearly"))
    rows("UPDATE users SET deleted_at=now() WHERE id<>14101")
    Ownership.put!(ScratchRepo, PreheatSweepWorker.key(), :oban)
    Ownership.put!(ScratchRepo, "command:cache.preheat_user", :sidekiq, pinned: true)
    :ok
  end

  @tag a12f3b_case: "E08a"
  test "E08 native owner accepts every retained argument and continuation shape" do
    now = 1_791_028_800

    for zone <- [nil, "Asia/Tokyo"] do
      source = Ecto.UUID.generate()
      opts = [source_job_id: source, clock: now, schedule_in: 3600]
      opts = if zone, do: Keyword.put(opts, :time_zone, zone), else: opts
      assert PreheatSweepWorker.run(ScratchRepo, opts) == :ok
      event = child_id(source, 14101)

      assert [[args, at]] =
               rows("SELECT args,scheduled_at FROM oban.oban_jobs WHERE args->>'event_id'=$1", [
                 event
               ])

      assert args == %{
               "user_id" => 14101,
               "time_zone" => zone || System.get_env("TIME_ZONE", "Europe/Berlin"),
               "source_job_id" => event,
               "event_id" => event
             }

      assert NaiveDateTime.compare(at, DateTime.from_unix!(now + 3600) |> DateTime.to_naive()) ==
               :eq

      assert PreheatSweepWorker.run(ScratchRepo, opts) == :ok

      assert [[1]] =
               rows("SELECT count(*) FROM oban.oban_jobs WHERE args->>'event_id'=$1", [event])

      assert [[0]] = rows("SELECT count(*) FROM phoenix.rails_commands")
      options = Keyword.delete(F.options(F.case!("berlin_yearly")), :uuid)
      assert PreheatUserWorker.run(ScratchRepo, args, options) == :ok
      assert Processed.done?(ScratchRepo, event)
      assert length(F.digests(ScratchRepo, 14101)) == 2

      for suffix <-
            ~w(years_tracked points_geocoded_stats countries_visited cities_visited total_distance) do
        assert {:ok, ttl} = Redis.cache_command(["TTL", "phoenix/dawarich/user_14101_" <> suffix])
        assert ttl in 1..86400
      end
    end

    args = %{
      "user_id" => 14101,
      "time_zone" => "Asia/Tokyo",
      "source_job_id" => Ecto.UUID.generate(),
      "event_id" => Ecto.UUID.generate()
    }

    fault = %RuntimeError{message: "synthetic warming failure"}
    options = [before_warm_write: fn _ -> raise fault end]
    {:ok, _} = Redis.cache_command(["FLUSHDB"])
    assert PreheatUserWorker.run(ScratchRepo, args, options) == {:error, fault}
    refute Processed.done?(ScratchRepo, args["event_id"])
    assert PreheatUserWorker.perform(%Oban.Job{args: args}) == :ok
    assert Processed.done?(ScratchRepo, args["event_id"])
    assert PreheatUserWorker.run(ScratchRepo, args, options) == :ok

    for id <- [14102, 14199] do
      missing = %{args | "user_id" => id, "event_id" => Ecto.UUID.generate()}
      assert PreheatUserWorker.perform(%Oban.Job{args: missing}) == :ok
      assert Processed.done?(ScratchRepo, missing["event_id"])
      assert {:ok, []} = Redis.cache_command(["KEYS", "phoenix/dawarich/user_#{id}_*"])
    end

    Ownership.put!(ScratchRepo, PreheatSweepWorker.key(), :sidekiq, pinned: true)
    assert PreheatSweepWorker.run(ScratchRepo) == {:cancel, :not_owner}

    due = DateTime.from_unix!(now)
    accepted = %Oban.Job{id: 809, args: %{}, scheduled_at: due}
    assert PreheatSweepWorker.perform(accepted) == :ok
    parent_source = :crypto.hash(:md5, "cache-sweep/809/#{due}") |> Ecto.UUID.load!()
    event = child_id(parent_source, 14101)

    assert [[args, at]] =
             rows("SELECT args,scheduled_at FROM oban.oban_jobs WHERE args->>'event_id'=$1", [
               event
             ])

    assert args["time_zone"] == System.get_env("TIME_ZONE", "Europe/Berlin")
    assert NaiveDateTime.compare(at, DateTime.to_naive(due)) == :eq
    assert PreheatSweepWorker.perform(accepted) == :ok
    assert [[1]] = rows("SELECT count(*) FROM oban.oban_jobs WHERE args->>'event_id'=$1", [event])
    assert [[0]] = rows("SELECT count(*) FROM phoenix.rails_commands")
    assert [[0]] = rows("SELECT count(*) FROM public.job_outbox")
  end

  @tag a12f3b_case: "E08b"
  test "E08 source accepted chain remains visible until all children settle" do
    source = Ecto.UUID.generate()
    due = ~U[2026-10-03 12:00:00Z]
    opts = [source_job_id: source, clock: DateTime.to_unix(due), time_zone: "Asia/Tokyo"]
    rows("UPDATE users SET deleted_at=NULL WHERE id=14102")

    rows(
      "ALTER TABLE oban.oban_jobs ADD CONSTRAINT e08_reject_last_child CHECK (worker<>'Dawarich.Cache.PreheatUserWorker' OR args->>'user_id'<>'14102') NOT VALID"
    )

    assert {:error, %Ecto.ConstraintError{constraint: "e08_reject_last_child"}} =
             PreheatSweepWorker.run(ScratchRepo, opts)

    assert [[0]] = rows("SELECT count(*) FROM oban.oban_jobs")
    assert [[0]] = rows("SELECT count(*) FROM phoenix.rails_commands")
    rows("ALTER TABLE oban.oban_jobs DROP CONSTRAINT e08_reject_last_child")

    assert PreheatSweepWorker.run(ScratchRepo, opts) == :ok
    status = Drain.status(ScratchRepo)
    assert status.counts.incomplete_oban == 2
    assert status.counts.reverse_pending == 0
    assert status.shutdown == "BLOCKED"
    assert "incomplete_oban" in status.shutdown_reasons

    Ownership.put!(ScratchRepo, PreheatSweepWorker.key(), :sidekiq, pinned: true)

    parent = %Oban.Job{
      id: 808,
      args: %{"source_job_id" => source, "time_zone" => "Asia/Tokyo"},
      scheduled_at: due
    }

    assert PreheatSweepWorker.perform(parent) == :ok
    children = rows("SELECT id,args FROM oban.oban_jobs ORDER BY id")
    assert length(children) == 2

    for {[id, args], remaining} <- Enum.zip(children, [1, 0]) do
      assert args["event_id"] == child_id(source, args["user_id"])
      fault = %RuntimeError{message: "synthetic failure before settlement"}

      assert PreheatUserWorker.run(ScratchRepo, args, after_preheat: fn -> raise fault end) ==
               {:error, fault}

      refute Processed.done?(ScratchRepo, args["event_id"])
      assert Drain.status(ScratchRepo).counts.incomplete_oban == remaining + 1
      assert PreheatUserWorker.perform(%Oban.Job{args: args}) == :ok
      assert Processed.done?(ScratchRepo, args["event_id"])
      rows("UPDATE oban.oban_jobs SET state='completed',completed_at=now() WHERE id=$1", [id])
      assert Drain.status(ScratchRepo).counts.incomplete_oban == remaining
    end

    assert PreheatSweepWorker.perform(parent) == :ok
    status = Drain.status(ScratchRepo)
    assert status.counts.incomplete_oban == 0
    refute "incomplete_oban" in status.shutdown_reasons
    assert status.counts.reverse_pending == 0
    assert status.counts.pending_outbox == 0
    assert [[2]] = rows("SELECT count(*) FROM oban.oban_jobs")
  after
    rows("ALTER TABLE oban.oban_jobs DROP CONSTRAINT IF EXISTS e08_reject_last_child")
  end

  defp child_id(source, id),
    do: :crypto.hash(:md5, "#{source}/#{id}") |> Ecto.UUID.load!()
end

defmodule Dawarich.Jobs.ScheduleCutoverTest do
  use Dawarich.JobsCase

  alias Dawarich.Integrations.SyncScheduling
  alias Dawarich.Jobs.{Claimer, Drain, Housekeeping, Ownership, Processed, Registry}
  alias Dawarich.RailsCommands

  @oban __MODULE__.Oban

  setup do
    start_oban(@oban)
    previous = System.get_env("SELF_HOSTED")
    System.put_env("SELF_HOSTED", "true")

    on_exit(fn ->
      if previous,
        do: System.put_env("SELF_HOSTED", previous),
        else: System.delete_env("SELF_HOSTED")
    end)

    [[user]] =
      rows("""
      INSERT INTO users (email, settings, created_at, updated_at)
      VALUES ('cutover@example.test', '{"teslamate_url":"https://synthetic.example"}', now(), now())
      RETURNING id
      """)

    [[source]] =
      rows("""
      INSERT INTO trip_sources (user_id, status, provider, base_url, api_key, created_at, updated_at)
      VALUES (#{user}, 0, 'trek', 'https://synthetic.example', 'synthetic', now(), now()) RETURNING id
      """)

    %{user: user, source: source}
  end

  defp entry(kind), do: Enum.find(Registry.entries(), &(&1.key == SyncScheduling.key(kind)))

  defp fanouts, do: rows("SELECT kind, payload FROM phoenix.rails_commands ORDER BY id")

  defp source_batch(kind, slot, id, user) do
    Ownership.with_owner(ScratchRepo, SyncScheduling.key(kind), :sidekiq, fn ->
      if Processed.claim!(
           ScratchRepo,
           SyncScheduling.receipt_id(kind, slot, id),
           "Integrations::SchedulingCommands"
         ) do
        payload = %{"user_id" => user, "event_id" => SyncScheduling.event_id(kind, slot, id)}
        payload = if kind == :trek, do: Map.put(payload, "source_id", id), else: payload
        RailsCommands.insert!(ScratchRepo, "integrations.#{kind}_sync", payload)
      end
    end)
  end

  @tag a12f3b_case: "G01b"
  test "the same source and native schedule slot commits fanout once including a claim at the due minute",
       context do
    for timestamp <- [
          "2026-03-29T01:30:00+01:00",
          "2026-10-25T02:30:00+02:00",
          "2026-10-25T02:30:00+01:00"
        ],
        {kind, id, old_worker} <- [
          {:teslamate, context.user, Dawarich.Imports.Teslamate.ScheduleWorker},
          {:trek, context.source, Dawarich.Imports.Trek.ScheduleWorker}
        ] do
      rows("DELETE FROM phoenix.processed_commands")
      rows("DELETE FROM phoenix.rails_commands")
      rows("DELETE FROM oban.oban_jobs")
      Ownership.put!(ScratchRepo, SyncScheduling.key(kind), :sidekiq)
      {:ok, due, _} = DateTime.from_iso8601(timestamp)

      slot =
        SyncScheduling.slot(%Oban.Job{inserted_at: due, scheduled_at: DateTime.add(due, 3600)})

      old = Oban.insert!(@oban, old_worker.new(%{}))

      assert Claimer.claim(ScratchRepo, @oban, entry(kind)) ==
               {:error, {:legacy_scheduler_jobs, 1}}

      Ownership.put!(ScratchRepo, SyncScheduling.key(kind), :oban)

      assert SyncScheduling.run(ScratchRepo, @oban, kind, slot) ==
               {:error, {:legacy_scheduler_jobs, 1}}

      assert fanouts() == []
      assert rows("SELECT state FROM oban.oban_jobs WHERE id = $1", [old.id]) == [["available"]]
      Ownership.put!(ScratchRepo, SyncScheduling.key(kind), :sidekiq)
      assert source_batch(kind, slot, id, context.user) == {:ok, :ok}
      published = fanouts()
      assert length(published) == 1

      rows("UPDATE oban.oban_jobs SET state = 'completed', completed_at = now() WHERE id = $1", [
        old.id
      ])

      assert Claimer.claim(ScratchRepo, @oban, entry(kind)) == :claimed
      assert rows("SELECT count(*) FROM oban.oban_jobs WHERE state <> 'completed'") == [[0]]
      assert SyncScheduling.run(ScratchRepo, @oban, kind, slot) == :ok
      assert fanouts() == published
      Ownership.put!(ScratchRepo, SyncScheduling.key(kind), :sidekiq, pinned: true)
      source_batch(kind, slot, id, context.user)
      assert fanouts() == published
      assert Claimer.claim(ScratchRepo, @oban, entry(kind)) == :pinned
    end

    for {key, worker} <- [
          {"cron:teslamate_sync_job", Dawarich.Imports.Teslamate.ScheduleWorker},
          {"cron:trek_sync_job", Dawarich.Imports.Trek.ScheduleWorker}
        ],
        state <- ~w(available executing scheduled retryable discarded) do
      rows("DELETE FROM oban.oban_jobs")
      entry = Enum.find(Registry.entries(), &(&1.key == key))
      job = Oban.insert!(@oban, worker.new(%{}))
      rows("UPDATE oban.oban_jobs SET state=$1 WHERE id=$2", [state, job.id])
      Ownership.put!(ScratchRepo, key, :sidekiq)
      assert Claimer.legacy_scheduler_count(ScratchRepo, key) == 1
      assert Claimer.claim(ScratchRepo, @oban, entry) == {:error, {:legacy_scheduler_jobs, 1}}
      assert "legacy_schedulers" in Drain.status(ScratchRepo).forward_reasons
      assert rows("SELECT state FROM oban.oban_jobs WHERE id=$1", [job.id]) == [[state]]
      rows("UPDATE oban.oban_jobs SET state='completed' WHERE id=$1", [job.id])
      assert Claimer.claim(ScratchRepo, @oban, entry) == :claimed
    end

    for %{kind: :cron} = cron <- Registry.entries(), do: assert(cron.catch_up == false)
  end

  test "aged schedule receipt survives housekeeping and delayed replay publishes no second fanout",
       %{user: user} do
    {:ok, due, _} = DateTime.from_iso8601("2025-10-26T02:30:00+01:00")
    slot = SyncScheduling.slot(%Oban.Job{inserted_at: due})
    source_batch(:teslamate, slot, user, user)
    published = fanouts()
    receipt = SyncScheduling.receipt_id(:teslamate, slot, user)
    rows("UPDATE phoenix.processed_commands SET processed_at = $1", [due])
    :ok = Housekeeping.run!(ScratchRepo, ~U[2026-10-05 10:00:00Z])
    assert Processed.done?(ScratchRepo, receipt)
    Ownership.put!(ScratchRepo, SyncScheduling.key(:teslamate), :oban)
    assert SyncScheduling.run(ScratchRepo, @oban, :teslamate, slot) == :ok
    assert fanouts() == published
  end

  @tag :rails_parity
  test "native schedule peer shares source slots and ownership fences", %{user: user} do
    database = ScratchRepo.config()[:database]
    assert database == System.fetch_env!("PHOENIX_TEST_DATABASE") <> "_scratch"
    assert String.starts_with?(database, "dawarich_phoenix_test")
    peer_send(%{op: "ready", database: database, user: user})
    schedule_peer()
  end

  defp schedule_peer do
    case IO.gets(:stdio, "") |> Jason.decode!() do
      %{"op" => "claim", "expected" => expected} ->
        result = Claimer.claim(ScratchRepo, @oban, entry(:teslamate), "100ms")
        assert inspect(result) == expected
        peer_send(%{op: "claimed"})
        schedule_peer()

      %{"op" => "run", "slot" => slot} ->
        assert SyncScheduling.run(ScratchRepo, @oban, :teslamate, slot) == :ok
        assert fanouts() == []
        peer_send(%{op: "ran"})
        schedule_peer()

      %{"op" => "hold", "slot" => slot} ->
        parent = self()

        hook = fn _ ->
          [[pid]] = rows("SELECT pg_backend_pid()")
          send(parent, {:held, self(), pid})
          receive(do: (:finish -> :ok))
        end

        task =
          Task.async(fn ->
            SyncScheduling.run(ScratchRepo, @oban, :teslamate, slot, hook: hook)
          end)

        assert_receive {:held, task_pid, pid}, 5_000
        peer_send(%{op: "held", pid: pid})
        assert %{"op" => "finish"} = IO.gets(:stdio, "") |> Jason.decode!()
        send(task_pid, :finish)
        assert Task.await(task) == :ok
        peer_send(%{op: "ran"})
        schedule_peer()

      %{"op" => "stop"} ->
        peer_send(%{op: "done"})
    end
  end

  defp peer_send(message), do: IO.puts("A12D3:" <> Jason.encode!(message))
end

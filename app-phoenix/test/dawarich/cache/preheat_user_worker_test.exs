defmodule Dawarich.Cache.PreheatUserWorkerTest do
  use Dawarich.JobsCase

  alias Dawarich.Cache.PreheatUserWorker, as: Worker
  alias Dawarich.DigestFixtures, as: F

  setup do
    for spec <- Dawarich.Redis.cache_child_specs(), do: start_supervised!(spec)
    {:ok, _} = Dawarich.Redis.cache_command(["FLUSHDB"])
    :ok
  end

  test "replayed forwarded preheat settles the event once and a crash before settlement converges" do
    kase = F.case!("berlin_yearly")
    F.load!(ScratchRepo, kase)
    opts = Keyword.delete(F.options(kase), :uuid)
    event = Ecto.UUID.generate()
    payload = %{"user_id" => 14101, "time_zone" => "Europe/Berlin", "source_job_id" => event}

    outbox!(
      event_id: event,
      command_type: "cache.preheat_user",
      payload: payload,
      scheduled_at: opts[:now]
    )

    start_oban(CacheReplay)
    commands = fn "cache.preheat_user" -> {:ok, Worker} end

    assert Dawarich.Jobs.Dispatch.run(
             repo: ScratchRepo,
             oban: CacheReplay,
             commands: commands,
             now: opts[:now]
           ) == %{dispatched: 1}

    [[args]] = rows("SELECT args FROM oban.oban_jobs")
    assert args["event_id"] == event
    assert args["source_job_id"] == event
    fault = %RuntimeError{message: "crash before preheat settlement"}
    failing = Keyword.put(opts, :after_preheat, fn -> raise fault end)
    assert Worker.run(ScratchRepo, args, failing) == {:error, fault}
    assert [[0]] = rows("SELECT count(*) FROM phoenix.processed_commands")
    assert length(F.digests(ScratchRepo, 14101)) == 2
    before = F.digests(ScratchRepo, 14101)
    assert Worker.perform(%Oban.Job{args: args}) == :ok
    assert Worker.run(ScratchRepo, args, failing) == :ok
    assert F.digests(ScratchRepo, 14101) == before

    assert [[1]] =
             rows("SELECT count(*) FROM phoenix.processed_commands WHERE event_id=$1", [
               Ecto.UUID.dump!(event)
             ])

    assert [["dispatched"]] =
             rows("SELECT state FROM public.job_outbox WHERE event_id=$1", [
               Ecto.UUID.dump!(event)
             ])

    assert [[0]] = rows("SELECT count(*) FROM phoenix.rails_commands")
  end

  test "concurrent native preheats preserve one indexed yearly row and sharing metadata" do
    kase = F.case!("berlin_yearly")
    F.load!(ScratchRepo, kase)
    rows("DELETE FROM stats WHERE user_id=14101 AND year<>2025")
    parent = self()
    opts = Keyword.delete(F.options(kase), :uuid)

    barrier = fn _context ->
      send(parent, {:ready, self()})
      receive do: (:store -> :ok)
    end

    calculate = fn repo, id, year, options ->
      result = Dawarich.Digests.Calculation.yearly(repo, id, year, options)
      send(parent, {:calculated_result, result})
      result
    end

    options = opts |> Keyword.put(:before_store, barrier) |> Keyword.put(:calculate, calculate)

    payload = %{
      "user_id" => 14101,
      "time_zone" => "Europe/Berlin",
      "source_job_id" => Ecto.UUID.generate()
    }

    first = Task.async(fn -> Worker.run(ScratchRepo, payload, options) end)
    second = Task.async(fn -> Worker.run(ScratchRepo, payload, options) end)
    assert_receive {:ready, first_pid}, 5000
    assert_receive {:ready, second_pid}, 5000
    refute first_pid == second_pid
    send(first_pid, :store)
    send(second_pid, :store)
    assert Task.await(first) == :ok
    assert Task.await(second) == :ok
    assert_receive {:calculated_result, {:ok, id}}
    assert_receive {:calculated_result, {:ok, ^id}}
    [digest] = F.digests(ScratchRepo, 14101)
    assert digest["id"] == id
    assert {:ok, _} = Ecto.UUID.cast(digest["sharing_uuid"])

    rows(
      "UPDATE digests SET sharing_settings='{\"enabled\":true}',sent_at='2026-10-01 12:00:00' WHERE id=$1",
      [id]
    )

    before = F.digests(ScratchRepo, 14101)
    assert Worker.run(ScratchRepo, payload, opts) == :ok
    assert F.digests(ScratchRepo, 14101) == before
  end

  test "decodes only v1 user timezone and stable source job UUID and runs durable preheat" do
    payload = %{
      "user_id" => 14101,
      "time_zone" => "Europe/Berlin",
      "source_job_id" => Ecto.UUID.generate()
    }

    assert Worker.args_from_command(1, payload) == {:ok, payload}
    job = Worker.new(payload) |> Ecto.Changeset.apply_changes()
    assert job.args == payload
    assert job.queue == "projections"
    assert job.max_attempts == 3

    invalid = [
      Map.delete(payload, "source_job_id"),
      Map.put(payload, "source_job_id", nil),
      Map.put(payload, "source_job_id", "bad-uuid"),
      Map.put(payload, "source_job_id", "00000000-0000-4000-8000-00000000000z"),
      Map.put(payload, "source_job_id", 123),
      Map.put(payload, "user_id", "14101"),
      Map.put(payload, "user_id", 1.5),
      Map.put(payload, "time_zone", nil),
      Map.put(payload, "run_at", "2026-10-03T12:00:00Z"),
      Map.put(payload, "extra", false)
    ]

    for bad <- invalid do
      assert Worker.args_from_command(1, bad) == {:error, "invalid_payload"}
      assert Worker.run(ScratchRepo, bad) == {:error, "invalid_payload"}
    end

    for version <- [0, 2, "1"],
        do: assert(Worker.args_from_command(version, payload) == {:error, "unsupported_version"})

    assert [[0]] = rows("SELECT count(*) FROM digests")
    kase = F.case!("berlin_yearly")
    F.load!(ScratchRepo, kase)
    assert Worker.run(ScratchRepo, payload, Keyword.delete(F.options(kase), :uuid)) == :ok
    digest = Enum.find(F.digests(ScratchRepo, 14101), &(&1["year"] == 2025))
    assert digest["distance"] == hd(kase["expected"]["rows"])["distance"]
    assert digest["travel_patterns"] == hd(kase["expected"]["rows"])["travel_patterns"]
    assert [[0]] = rows("SELECT count(*) FROM phoenix.rails_commands")
    assert Worker.perform(%Oban.Job{args: payload}) == :ok
  end
end

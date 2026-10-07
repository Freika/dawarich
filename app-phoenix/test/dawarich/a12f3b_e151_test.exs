defmodule Dawarich.A12f3bE151Test do
  use Dawarich.JobsCase

  alias Dawarich.Jobs.{Drain, Ownership}
  alias Dawarich.ReleaseOperations
  alias Dawarich.ReleaseOperations.Transportation
  alias Dawarich.Transportation.ReclassifyTrackWorker
  alias Dawarich.Wave6Fixtures

  setup do
    Wave6Fixtures.reset!()
    start_oban(__MODULE__)
    start_supervised!(hd(Dawarich.Redis.child_specs()))
    start_supervised!(hd(Dawarich.Redis.cache_child_specs()))

    for key <- ~w(command:transportation.reclassify_track command:tracks.generate_range),
        do: Ownership.put!(ScratchRepo, key, :oban)

    %{user: Wave6Fixtures.user!()}
  end

  @tag a12f3b_case: "E151a"
  test "E151 native source shapes reach their terminal effects", %{user: user} do
    track = Wave6Fixtures.track!(user)
    event = Ecto.UUID.generate()

    args = %{
      "event_id" => event,
      "version" => 1,
      "cursor" => %{"scope" => "missing", "from_track_id" => 0}
    }

    before = DateTime.utc_now()

    assert ReleaseOperations.run(ScratchRepo, __MODULE__, Transportation, job(args)) == :ok
    assert [[child, due]] = children()
    assert child["track_id"] == track
    assert child["user_id"] == user
    assert child["report_progress"] == false
    assert {:ok, _} = Ecto.UUID.cast(child["event_id"])
    assert DateTime.compare(DateTime.from_naive!(due, "Etc/UTC"), DateTime.add(before, -1)) != :lt
    assert ReclassifyTrackWorker.run(ScratchRepo, __MODULE__, child) == :ok
    assert rows("SELECT kind FROM phoenix.rails_commands") == []

    assert ReleaseOperations.run(ScratchRepo, __MODULE__, Transportation, job(args)) == :ok
    assert length(children()) == 1
  end

  @tag a12f3b_case: "E151b"
  test "E151 accepted children prevent premature completion", %{user: user} do
    Wave6Fixtures.track!(user)
    event = Ecto.UUID.generate()

    args = %{
      "event_id" => event,
      "version" => 1,
      "cursor" => %{"scope" => "all", "from_track_id" => 0}
    }

    assert ReleaseOperations.run(ScratchRepo, __MODULE__, Transportation, job(args)) == :ok
    assert [[child, _]] = children()

    assert [[next]] =
             rows("SELECT args FROM oban.oban_jobs WHERE worker = $1", [inspect(Transportation)])

    assert next["operation_id"] == event
    assert Drain.status(ScratchRepo).counts.release_pending == 1

    assert ReleaseOperations.run(ScratchRepo, __MODULE__, Transportation, job(next)) == :ok

    rows("UPDATE oban.oban_jobs SET state = 'completed' WHERE worker = $1", [
      inspect(Transportation)
    ])

    status = Drain.status(ScratchRepo)
    assert status.counts.release_pending == 0
    assert status.counts.incomplete_oban == 1
    assert "incomplete_oban" in status.shutdown_reasons
    assert status.counts.reverse_pending == 0

    assert ReclassifyTrackWorker.run(ScratchRepo, __MODULE__, child) == :ok

    rows("UPDATE oban.oban_jobs SET state = 'completed' WHERE worker = $1", [
      inspect(ReclassifyTrackWorker)
    ])

    assert Drain.status(ScratchRepo).counts.incomplete_oban == 1
    assert %{success: 1, failure: 0} = Oban.drain_queue(__MODULE__, queue: :tracks)
    assert Drain.status(ScratchRepo).counts.incomplete_oban == 0
  end

  defp children,
    do:
      rows("SELECT args, scheduled_at FROM oban.oban_jobs WHERE worker = $1 ORDER BY id", [
        inspect(ReclassifyTrackWorker)
      ])

  defp job(args), do: %Oban.Job{args: args, attempt: 1, max_attempts: 10}
end

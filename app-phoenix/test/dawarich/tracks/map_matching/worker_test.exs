Code.require_file("support.exs", __DIR__)

defmodule Dawarich.Tracks.MapMatching.WorkerTest do
  use Dawarich.TracksCase, async: false
  alias Dawarich.Tracks.MapMatching.{Enqueuer, State, Worker}
  alias Dawarich.MapMatching.{Atlas.Client.Error, TestSupport}

  setup do
    TestSupport.setup!()
    track = TestSupport.input!(ScratchRepo)
    assert :enqueued = Enqueuer.call(ScratchRepo, track.id)
    [args] = TestSupport.jobs(ScratchRepo, track.id)
    %{id: track.id, job: %Oban.Job{args: args, attempt: 1, max_attempts: 5}}
  end

  test "worker discards a response whose digest is no longer current", %{id: id, job: job} do
    Application.put_env(:dawarich, :map_matching_client, fn url, payload ->
      State.write!(ScratchRepo, id, %{status: :pending, digest: "replacement"})
      TestSupport.success(url, payload)
    end)

    assert :ok = Worker.run(ScratchRepo, job)

    assert %{status: :pending, digest: "replacement", matched_path: nil} =
             State.read(ScratchRepo, id)

    assert tracks_changed() == []
  end

  test "429 snoozes with Retry-After", %{id: id, job: job} do
    Application.put_env(:dawarich, :map_matching_client, fn _, _ ->
      {:error, %Error{code: "capacity", status: 429, transient?: true, retry_after: 37}}
    end)

    assert {:snooze, 37} = Worker.run(ScratchRepo, job)
    assert State.read(ScratchRepo, id).status == :pending
  end

  test "5 transient failures → failed with sanitized error", %{id: id, job: job} do
    Application.put_env(:dawarich, :map_matching_client, fn _, _ ->
      {:error,
       %Error{
         code: "unsafe coordinates 13 52",
         status: 503,
         transient?: true,
         message: "secret upstream body"
       }}
    end)

    for attempt <- 1..4 do
      assert {:error, %Error{code: "provider_error", message: "Atlas request failed"}} =
               Worker.run(ScratchRepo, %{job | attempt: attempt})

      assert State.read(ScratchRepo, id).status == :pending
    end

    assert :ok = Worker.run(ScratchRepo, %{job | attempt: 5})
    state = State.read(ScratchRepo, id)
    assert state.status == :failed

    assert state.data["error"] == %{
             "code" => "provider_error",
             "status" => 503,
             "attempt" => 5,
             "message" => "provider_error"
           }

    refute Jason.encode!(state.data) =~ "secret"
    assert [%{"updated" => [^id]}] = tracks_changed()
  end

  test "current result publishes through track-change effects without changing recorded input", %{
    id: id,
    job: job
  } do
    Application.put_env(:dawarich, :map_matching_client, &TestSupport.success/2)

    before =
      rows("SELECT ST_AsText(original_path),lock_version,updated_at FROM tracks WHERE id=$1", [id])

    assert %{success: 1, failure: 0} = Oban.drain_queue(oban(), queue: :map_matching)
    assert %{status: :matched, matched_path: %Geo.MultiLineString{}} = State.read(ScratchRepo, id)

    assert rows(
             "SELECT ST_AsText(original_path),lock_version,updated_at FROM tracks WHERE id=$1",
             [id]
           ) == before

    assert [%{"updated" => [^id]}] = tracks_changed()
    assert :ok = Worker.run(ScratchRepo, job)
    assert length(tracks_changed()) == 1
  end

  test "changed input and disabled pending jobs never call Atlas", %{id: id, job: job} do
    Application.put_env(:dawarich, :map_matching_client, fn _, _ ->
      flunk("stale or disabled job called Atlas")
    end)

    rows("UPDATE points SET accuracy=51 WHERE track_id=$1", [id])
    assert :ok = Worker.run(ScratchRepo, job)
    assert State.read(ScratchRepo, id).status == :pending
    System.put_env("MAP_MATCHING_ENABLED", "false")
    assert :ok = Worker.run(ScratchRepo, job)
    assert tracks_changed() == []
  end
end

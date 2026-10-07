Code.require_file("support.exs", __DIR__)

defmodule Dawarich.Tracks.MapMatching.DispatchRegressionTest do
  use Dawarich.TracksCase, async: false
  import ExUnit.CaptureLog
  alias Dawarich.MapMatching.TestSupport
  alias Dawarich.Tracks.Builder
  alias Dawarich.Tracks.MapMatching.{State, Sweeper}
  @tasks Dawarich.Tracks.MapMatching.Tasks

  setup do
    TestSupport.setup!()
  end

  @tag :r2_missing
  test "R2 missing optional supervisor never exits completed Builder and sweeper recovers" do
    track = TestSupport.input!(ScratchRepo)

    digest =
      Dawarich.MapMatching.Fingerprint.call(
        Dawarich.MapMatching.Input.load(ScratchRepo, track.id)
      )

    State.write!(ScratchRepo, track.id, %{status: :matched, digest: digest})
    rows("UPDATE points SET accuracy=59 WHERE track_id=$1", [track.id])
    :ok = Supervisor.terminate_child(Dawarich.Supervisor, @tasks)

    try do
      log =
        capture_log(fn ->
          assert {:ok, %{id: id}} =
                   Builder.create_track!(ScratchRepo, track.user, track.points, 100)

          assert id == track.id
          TestSupport.await_hooks!()
        end)

      assert log =~ "map_matching.dispatch_failed"
      assert TestSupport.jobs(ScratchRepo, track.id) == []
    after
      assert {:ok, _} = Supervisor.restart_child(Dawarich.Supervisor, @tasks)
    end

    assert :ok = Sweeper.run(ScratchRepo)
    assert State.read(ScratchRepo, track.id).status == :pending
    assert length(TestSupport.jobs(ScratchRepo, track.id)) == 1
  end

  @tag :r2_suspended
  test "R2 suspended supervisor cannot delay Builder and dispatch times out without late work" do
    track = TestSupport.input!(ScratchRepo)
    supervisor = Process.whereis(@tasks)
    :ok = :sys.suspend(supervisor)

    builder =
      Task.async(fn ->
        receive do: (:go -> Builder.create_track!(ScratchRepo, track.user, track.points, 100))
      end)

    try do
      log =
        capture_log(fn ->
          send(builder.pid, :go)
          assert {:ok, {:ok, %{id: id}}} = Task.yield(builder, 200)
          assert id == track.id
          Dawarich.MapMatchingTasks.await_dispatch!()
        end)

      assert log =~ "map_matching.dispatch_failed"
      assert TestSupport.jobs(ScratchRepo, track.id) == []
    after
      :ok = :sys.resume(supervisor)
      if Process.alive?(builder.pid), do: Task.await(builder)
      TestSupport.await_hooks!()
    end

    assert TestSupport.jobs(ScratchRepo, track.id) == []
    assert :ok = Sweeper.run(ScratchRepo)
    assert length(TestSupport.jobs(ScratchRepo, track.id)) == 1
  end
end

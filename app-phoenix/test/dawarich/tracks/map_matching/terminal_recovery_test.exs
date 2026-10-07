Code.require_file("support.exs", __DIR__)

defmodule Dawarich.Tracks.MapMatching.TerminalRecoveryTest do
  use Dawarich.TracksCase, async: false
  alias Dawarich.MapMatching.TestSupport
  alias Dawarich.MapMatching.Atlas.Client.Error
  alias Dawarich.Tracks.MapMatching.{Enqueuer, State, Sweeper}

  setup do
    TestSupport.setup!()
  end

  @tag :r2_terminal_recovery
  test "R2 sweeper preserves exhausted 429 input and recovers changed terminal input" do
    track = TestSupport.input!(ScratchRepo)
    assert :enqueued = Enqueuer.call(ScratchRepo, track.id)
    counter = start_supervised!({Agent, fn -> 0 end})

    Application.put_env(:dawarich, :map_matching_client, fn _, _ ->
      Agent.update(counter, &(&1 + 1))
      {:error, %Error{code: "capacity", status: 429, transient?: true, retry_after: 1}}
    end)

    for _ <- 1..5, do: Oban.drain_queue(oban(), queue: :map_matching, with_scheduled: true)
    assert State.read(ScratchRepo, track.id).status == :failed
    assert Agent.get(counter, & &1) == 5
    for _ <- 1..2, do: assert(:ok == Sweeper.run(ScratchRepo))
    assert State.read(ScratchRepo, track.id).status == :failed
    assert length(TestSupport.jobs(ScratchRepo, track.id)) == 1
    Oban.drain_queue(oban(), queue: :map_matching, with_scheduled: true)
    assert Agent.get(counter, & &1) == 5
    rows("UPDATE points SET accuracy=59 WHERE track_id=$1", [track.id])
    assert :ok = Sweeper.run(ScratchRepo)
    assert State.read(ScratchRepo, track.id).status == :pending
    assert length(TestSupport.jobs(ScratchRepo, track.id)) == 2
    assert :ok = Sweeper.run(ScratchRepo)
    assert length(TestSupport.jobs(ScratchRepo, track.id)) == 2
  end
end

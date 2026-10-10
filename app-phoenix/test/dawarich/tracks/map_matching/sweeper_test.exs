defmodule Dawarich.Tracks.MapMatching.SweeperTest do
  use Dawarich.TracksCase, async: false
  alias Dawarich.Tracks.MapMatching.{Enqueuer, State, Sweeper}
  alias Dawarich.MapMatching.TestSupport

  setup do
    TestSupport.setup!()
  end

  test "runtime config schedules the sweeper every 15 minutes and pins queue concurrency" do
    path = Path.expand("../../../../config/runtime.exs", __DIR__)
    config = Config.Reader.read!(path, env: :prod, target: :host)[:dawarich][Oban]
    assert config[:queues][:map_matching] == 2
    assert {"*/15 * * * *", Sweeper} in config[:cron][:crontab]
    before = Application.fetch_env!(:dawarich, Oban)
    Application.put_env(:dawarich, Oban, Keyword.put(before, :cron, config[:cron]))
    on_exit(fn -> Application.put_env(:dawarich, Oban, before) end)

    {Oban, options} =
      List.keyfind(Dawarich.Application.children({:native, {{127, 0, 0, 1}, 4000}}), Oban, 0)

    assert {Dawarich.Jobs.TickScheduler, cron} = options[:cron]
    assert {"*/15 * * * *", Sweeper} in cron[:crontab]
  end

  test "stale pending older than 1 h is re-enqueued by the sweeper, fresh pending is not" do
    old = TestSupport.input!(ScratchRepo)
    fresh = TestSupport.input!(ScratchRepo)
    for track <- [old, fresh], do: assert(:enqueued == Enqueuer.call(ScratchRepo, track.id))
    TestSupport.stale!(ScratchRepo, old.id)
    before = State.read(ScratchRepo, old.id)
    fresh_state = State.read(ScratchRepo, fresh.id)
    rows("UPDATE points SET accuracy=55 WHERE track_id=$1", [fresh.id])

    rows("UPDATE oban.oban_jobs SET state='discarded' WHERE args->>'track_id'=$1", [
      to_string(old.id)
    ])

    assert :ok = Sweeper.run(ScratchRepo)
    refute State.read(ScratchRepo, old.id).data == before.data
    assert State.read(ScratchRepo, fresh.id) == fresh_state
    assert length(TestSupport.jobs(ScratchRepo, old.id)) == 2
    assert length(TestSupport.jobs(ScratchRepo, fresh.id)) == 1
    assert :ok = Sweeper.run(ScratchRepo)
    assert length(TestSupport.jobs(ScratchRepo, old.id)) == 2
  end
end

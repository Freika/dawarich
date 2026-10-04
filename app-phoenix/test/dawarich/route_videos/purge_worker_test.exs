defmodule Dawarich.RouteVideos.PurgeWorkerTest do
  use Dawarich.JobsCase

  alias Dawarich.Jobs.Ownership
  alias Dawarich.RouteVideos.PurgeWorker

  @now ~U[2026-10-03 10:00:00Z]

  test "Rails-owned retention makes native worker a no-op" do
    ScratchRepo.insert_all("users", [
      %{
        id: 8860,
        email: "a8-purge@dawarich.test",
        encrypted_password: "synthetic",
        settings: %{},
        created_at: ~N[2026-10-03 10:00:00],
        updated_at: ~N[2026-10-03 10:00:00]
      }
    ])

    ScratchRepo.insert_all("route_videos", [
      %{
        id: 886_200,
        user_id: 8860,
        name: "Old route",
        status: 0,
        settings: %{},
        created_at: ~N[2026-08-01 10:00:00],
        updated_at: ~N[2026-08-01 10:00:00]
      }
    ])

    policy = %{retention_days: 30, max_per_user: 0}
    assert PurgeWorker.run(ScratchRepo, @now, policy) == {:cancel, :not_owner}
    assert [[0]] = rows("SELECT status FROM route_videos WHERE id=886200")
    Ownership.put!(ScratchRepo, "cron:route_videos_purge_job", :oban)
    assert PurgeWorker.run(ScratchRepo, @now, policy) == :ok
    assert [[1]] = rows("SELECT status FROM route_videos WHERE id=886200")
    assert PurgeWorker.run(ScratchRepo, DateTime.add(@now, 3600), policy) == :ok

    assert [[~N[2026-10-03 10:00:00.000000]]] =
             rows("SELECT expired_at FROM route_videos WHERE id=886200")
  end
end

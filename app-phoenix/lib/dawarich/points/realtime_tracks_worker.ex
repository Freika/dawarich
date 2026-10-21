defmodule Dawarich.Points.RealtimeTracksWorker do
  @moduledoc false
  use Oban.Worker, queue: :tracks, max_attempts: 1

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user} = args, conf: conf}) do
    repo = Dawarich.Jobs.repo()
    Dawarich.State.unclaim(repo, "track_realtime:user:#{user}")
    Dawarich.Tracks.RealtimeWorker.run(repo, conf.name, args)
  end
end

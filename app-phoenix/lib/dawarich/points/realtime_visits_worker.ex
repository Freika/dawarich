defmodule Dawarich.Points.RealtimeVisitsWorker do
  @moduledoc false
  use Oban.Worker, queue: :visit_suggesting, max_attempts: 1

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user} = args}) do
    repo = Dawarich.Jobs.repo()
    Dawarich.State.unclaim(repo, "visit_realtime:user:#{user}")
    Dawarich.Visits.Suggest.run(repo, user, args["start_at"], args["end_at"], args)
  end
end

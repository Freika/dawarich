defmodule Dawarich.RouteVideos.PurgeWorker do
  @moduledoc false
  use Oban.Worker,
    queue: :route_videos,
    max_attempts: 3,
    unique: [period: :infinity, states: :incomplete]

  alias Dawarich.Jobs.Ownership
  alias Dawarich.RouteVideos.Retention

  def key, do: "cron:route_videos_purge_job"

  @impl Oban.Worker
  def perform(%Oban.Job{}),
    do: run(Dawarich.Jobs.repo(), DateTime.utc_now(), Retention.policy(System.get_env()))

  def run(repo, now, policy) do
    case Ownership.with_owner(repo, key(), :oban, fn -> Retention.run(repo, now, policy) end) do
      {:ok, _} -> :ok
      {:skip, _} -> {:cancel, :not_owner}
    end
  end
end

defmodule Dawarich.Points.AnomalyArrivalWorker do
  @moduledoc false
  use Oban.Worker, queue: :projections, max_attempts: 1
  alias Dawarich.Points.NativeEffects

  def enqueue(repo, %{"user_id" => user} = payload) do
    if NativeEffects.native?(repo, "command:points.anomaly_filter") do
      case repo.query!("SELECT settings FROM users WHERE id=$1", [user], log: false).rows do
        [[settings]] ->
          args = Map.put(payload, "time_zone", Dawarich.UserTimeZone.iana(repo, settings))
          NativeEffects.enqueue(repo, __MODULE__, args)

        [] ->
          :ok
      end
    else
      Dawarich.RailsCommands.insert!(repo, "points.anomaly_filter", payload)
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}), do: run(Dawarich.Jobs.repo(), args)

  def run(repo, args) do
    if repo.query!("SELECT id FROM users WHERE id=$1", [args["user_id"]], log: false).num_rows ==
         1,
       do:
         Dawarich.Points.AnomalyFilter.call(
           repo,
           args["user_id"],
           args["start_at"],
           args["end_at"],
           zone: args["time_zone"]
         )

    :ok
  end
end

defmodule Dawarich.Points.AnomalyFilter.RecalculateWorker do
  @moduledoc false
  use Oban.Worker, queue: :tracks, max_attempts: 1
  alias Dawarich.Jobs.Ownership
  alias Dawarich.Tracks.RecalculateWorker

  def args_from_command(
        1,
        %{"track_id" => track, "user_id" => user, "job_queue" => queue} = payload
      )
      when is_integer(track) and is_integer(user) and
             (is_nil(queue) or (is_binary(queue) and byte_size(queue) > 0)) and
             map_size(payload) == 3,
      do: {:ok, payload}

  def args_from_command(1, _), do: {:error, "invalid_payload"}
  def args_from_command(_, _), do: {:error, "unsupported_version"}

  @impl Oban.Worker
  def new(args, opts), do: super(args, Keyword.put(opts, :queue, args["job_queue"] || "tracks"))

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}), do: run(Dawarich.Jobs.repo(), args)

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(10)

  def run(repo, %{"track_id" => track, "user_id" => user} = args) do
    if repo.query!("SELECT id FROM tracks WHERE id=$1 AND user_id=$2", [track, user], log: false).num_rows ==
         1 do
      if Dawarich.Standalone.enabled?() do
        RecalculateWorker.run(repo, nil, %{"track_id" => track})
      else
        case Ownership.with_owner(repo, "command:tracks.recalculate", :oban, fn ->
               RecalculateWorker.run(repo, nil, %{"track_id" => track})
             end) do
          {:ok, :ok} ->
            :ok

          {:skip, :sidekiq} ->
            Dawarich.RailsCommands.insert!(
              repo,
              "points.anomaly_recalculate",
              Map.take(args, ~w(user_id track_id job_queue))
            )
        end
      end
    else
      :ok
    end
  end
end

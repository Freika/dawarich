defmodule Dawarich.Tracks.RecalculateWorker do
  @moduledoc false
  use Oban.Worker, queue: :tracks, max_attempts: 1

  require Logger

  alias Dawarich.Tracks.Recalculator

  def args_from_command(1, %{"track_id" => id} = payload)
      when is_integer(id) and map_size(payload) == 1,
      do: {:ok, %{"track_id" => id}}

  def args_from_command(1, _payload), do: {:error, "invalid_payload"}
  def args_from_command(_version, _payload), do: {:error, "unsupported_version"}

  @impl Oban.Worker
  def perform(%Oban.Job{args: args, conf: conf}), do: run(Dawarich.Jobs.repo(), conf.name, args)

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(10)

  def run(repo, _oban, %{"track_id" => track_id}) do
    if Recalculator.run(repo, track_id) == :missing,
      do: Logger.warning("[Tracks::RecalculateJob] Track #{track_id} not found")

    :ok
  rescue
    error ->
      Logger.error("Failed to recalculate track #{track_id}: #{Exception.message(error)}")
      :ok
  end
end

defmodule Dawarich.Imports.Integrations.PhotoprismWorker do
  @moduledoc false
  use Oban.Worker,
    queue: :imports,
    max_attempts: 5,
    unique: [keys: [:event_id], states: :incomplete, period: :infinity]

  def args_from_command(version, args),
    do: Dawarich.Imports.Integrations.ImmichWorker.args_from_command(version, args)

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    Dawarich.Imports.Integrations.Photoprism.run(Dawarich.Jobs.repo(), args)
  rescue
    _ -> {:discard, :invalid_payload}
  end

  @impl Oban.Worker
  def backoff(job), do: Dawarich.Imports.Integrations.ImmichWorker.backoff(job)
end

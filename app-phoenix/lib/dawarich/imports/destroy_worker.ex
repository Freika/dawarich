defmodule Dawarich.Imports.DestroyWorker do
  @moduledoc false
  use Oban.Worker,
    queue: :imports,
    max_attempts: 3,
    unique: [keys: [:event_id], states: :incomplete, period: :infinity]

  alias Dawarich.Imports.{DestroyLease, DestroyService, DestroyHandover, LeaseLost}
  alias Dawarich.Jobs.Processed

  def args_from_command(1, %{"import_id" => id, "user_id" => user} = payload)
      when is_integer(id) and id > 0 and is_integer(user) and user > 0 and map_size(payload) == 2,
      do: {:ok, payload}

  def args_from_command(1, _), do: {:error, "invalid_payload"}
  def args_from_command(_, _), do: {:error, "unsupported_version"}
  @impl Oban.Worker
  def timeout(_), do: :timer.minutes(55)
  @impl Oban.Worker
  def perform(%Oban.Job{} = job) do
    repo = Dawarich.Jobs.repo()

    if Processed.done?(repo, job.args["event_id"]) do
      :ok
    else
      case DestroyLease.with_import(repo, job, &DestroyService.call/1) do
        {:ok, value} -> value
        {:skip, :busy} -> {:snooze, 5}
        {:skip, :foreign_dependents} -> {:cancel, "foreign import dependents"}
        {:skip, _} -> DestroyHandover.resume(repo, job)
      end
    end
  rescue
    LeaseLost -> DestroyHandover.resume(Dawarich.Jobs.repo(), job)
  end
end

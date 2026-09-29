defmodule Dawarich.Areas.RelabelWorker do
  @moduledoc false
  use Oban.Worker,
    queue: :projections,
    max_attempts: 2,
    unique: [keys: [:area_id], states: [:available, :scheduled, :retryable], period: :infinity]

  def args_from_command(1, %{"area_id" => id} = payload)
      when is_integer(id) and map_size(payload) == 1,
      do: {:ok, %{"area_id" => id}}

  def args_from_command(1, _payload), do: {:error, "invalid_payload"}
  def args_from_command(_version, _payload), do: {:error, "unsupported_version"}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"area_id" => id}}) do
    case Dawarich.Areas.relabel(Dawarich.Jobs.repo(), id) do
      outcome when outcome in [:ok, :missing] -> :ok
    end
  end
end

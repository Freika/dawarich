defmodule Dawarich.Trips.CalculateWorker do
  @moduledoc false
  use Oban.Worker,
    queue: :trips,
    max_attempts: 3,
    unique: [keys: [:trip_id], states: [:available, :scheduled, :retryable], period: :infinity]

  alias Dawarich.Trips.Calculation

  def args_from_command(1, %{"trip_id" => id, "distance_unit" => unit} = payload)
      when is_integer(id) and is_binary(unit) and map_size(payload) == 2,
      do: {:ok, %{"trip_id" => id, "distance_unit" => unit}}

  def args_from_command(1, _payload), do: {:error, "invalid_payload"}
  def args_from_command(_version, _payload), do: {:error, "unsupported_version"}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"trip_id" => id, "distance_unit" => unit}} = job) do
    Dawarich.Jobs.Processed.once(
      Dawarich.Jobs.repo(),
      job.args["event_id"],
      Atom.to_string(__MODULE__),
      fn ->
        case Calculation.run(Dawarich.Jobs.repo(), id, unit) do
          outcome when outcome in [:ok, :missing, :superseded] -> :ok
        end
      end
    )
  rescue
    exception ->
      if job.attempt >= job.max_attempts, do: Calculation.fail!(Dawarich.Jobs.repo(), id, unit)
      reraise exception, __STACKTRACE__
  end
end

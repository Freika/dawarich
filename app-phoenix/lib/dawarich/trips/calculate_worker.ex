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
    execute(job, fn ->
      case Calculation.run(Dawarich.Jobs.repo(), id, unit, fn _ -> :ok end, job.args["event_id"]) do
        outcome when outcome in [:ok, :missing, :superseded] -> :ok
      end
    end)
  rescue
    exception ->
      if job.attempt >= job.max_attempts do
        execute(job, fn -> Calculation.fail!(Dawarich.Jobs.repo(), id, unit) end)
      end

      reraise exception, __STACKTRACE__
  end

  defp execute(job, effect) do
    repo = Dawarich.Jobs.repo()

    case repo.transaction(fn ->
           if Dawarich.Jobs.Ownership.lock(repo, "command:trips.calculate") == :inconsistent do
             repo.rollback(:inconsistent)
           end

           repo.query!(
             "SELECT pg_advisory_xact_lock(hashtextextended($1::text, 0))",
             [job.args["event_id"]],
             log: false
           )

           Dawarich.Jobs.Processed.once(
             repo,
             job.args["event_id"],
             Atom.to_string(__MODULE__),
             effect
           )
         end) do
      {:ok, outcome} -> outcome
      {:error, reason} -> {:error, reason}
    end
  end
end

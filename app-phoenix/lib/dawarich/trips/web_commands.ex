defmodule Dawarich.Trips.WebCommands do
  @moduledoc false
  alias Dawarich.Jobs.Ownership

  def admission(repo) do
    case Ownership.lock(repo, "command:trips.calculate") do
      :oban -> :ok
      :sidekiq -> {:replay, "Sidekiq trip calculation"}
    end
  end

  def calculate!(repo, user, trip_id, unit, now) when unit in ~w(km mi m ft yd) do
    repo.transaction(fn ->
      with :ok <- admission(repo),
           %{rows: [[^trip_id]]} <-
             repo.query!(
               "SELECT id FROM trips WHERE id = $1 AND user_id = $2",
               [trip_id, user.id],
               log: false
             ) do
        result =
          repo.query!(
            """
            INSERT INTO public.job_outbox
              (event_id, command_type, command_version, payload, metadata, aggregate_id, dedupe_key, scheduled_at)
            VALUES (gen_random_uuid(), 'trips.calculate', 1, $1, $2, $3, $4, $5)
            ON CONFLICT DO NOTHING
            """,
            [
              %{"trip_id" => trip_id, "distance_unit" => unit},
              %{"producer" => "Trip#enqueue_calculation_jobs"},
              trip_id,
              Integer.to_string(trip_id),
              now
            ],
            log: false
          )

        {:ok, if(result.num_rows == 1, do: :queued, else: :pending)}
      else
        {:replay, _} = replay -> replay
        _ -> {:error, :not_found}
      end
    end)
    |> case do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end
end

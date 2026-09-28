defmodule Dawarich.AirTrail.ImportFlightsWorker do
  @moduledoc false
  use Oban.Worker,
    queue: :imports,
    max_attempts: 3,
    unique: [keys: [:user_id], states: [:available, :scheduled, :retryable], period: :infinity]

  alias Dawarich.AirTrail.{Client, Flights}
  alias Dawarich.Jobs.Processed

  def args_from_command(1, %{"user_id" => id} = payload)
      when is_integer(id) and map_size(payload) == 1,
      do: {:ok, %{"user_id" => id}}

  def args_from_command(1, _payload), do: {:error, "invalid_payload"}
  def args_from_command(_version, _payload), do: {:error, "unsupported_version"}

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(5)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"event_id" => event_id, "user_id" => user_id}}) do
    repo = Dawarich.Jobs.repo()

    with false <- Processed.done?(repo, event_id),
         %{} = source <- Flights.source(repo, user_id),
         {:ok, flights} <- Client.flights(source) do
      Flights.store!(
        repo,
        user_id,
        flights,
        event_id,
        System.get_env("TIME_ZONE", "Europe/Berlin")
      )
    else
      true -> :ok
      nil -> :ok
      {:error, message} -> Flights.fail!(repo, user_id, message)
    end
  end
end

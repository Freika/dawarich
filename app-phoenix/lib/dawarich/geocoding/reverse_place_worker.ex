defmodule Dawarich.Geocoding.ReversePlaceWorker do
  @moduledoc false
  use Oban.Worker, queue: :reverse_geocoding, max_attempts: 4

  alias Dawarich.Geocoding.{Config, PlaceFetch}

  def args_from_command(1, %{"place_id" => id} = p) when is_integer(id) and map_size(p) == 1,
    do: {:ok, %{"place_id" => id}}

  def args_from_command(1, _payload), do: {:error, "invalid_payload"}
  def args_from_command(_version, _payload), do: {:error, "unsupported_version"}

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(10)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"place_id" => place_id}}) do
    repo = Dawarich.Jobs.repo()

    case PlaceFetch.run(repo, place_id, Config.resolve(repo)) do
      outcome when outcome in [:ok, :missing] -> :ok
    end
  end
end

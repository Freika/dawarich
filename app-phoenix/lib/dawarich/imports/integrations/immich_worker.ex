defmodule Dawarich.Imports.Integrations.ImmichWorker do
  @moduledoc false
  use Oban.Worker,
    queue: :imports,
    max_attempts: 5,
    unique: [keys: [:event_id], states: :incomplete, period: :infinity]

  def args_from_command(1, %{"user_id" => id, "time_zone" => zone} = args)
      when is_integer(id) and id > 0 and is_binary(zone) and map_size(args) == 2 do
    Dawarich.Imports.ZonePeriod.load!(Dawarich.TimeZoneName.to_iana(zone))
    {:ok, args}
  rescue
    _ -> {:error, "invalid_payload"}
  end

  def args_from_command(1, _), do: {:error, "invalid_payload"}
  def args_from_command(_, _), do: {:error, "unsupported_version"}

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    Dawarich.Imports.Integrations.Immich.run(Dawarich.Jobs.repo(), args)
  rescue
    _ -> {:discard, :invalid_payload}
  end

  @impl Oban.Worker
  def backoff(job) do
    delay = :math.pow(job.attempt, 4)
    trunc(delay + 2 + :rand.uniform() * 0.15 * delay)
  end
end

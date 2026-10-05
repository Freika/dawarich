defmodule Dawarich.Cache.PreheatUserWorker do
  @moduledoc false
  use Oban.Worker, queue: :projections, max_attempts: 3

  alias Dawarich.Cache.PreheatDigests

  def args_from_command(
        1,
        %{"user_id" => id, "time_zone" => zone, "source_job_id" => uuid} = payload
      )
      when is_integer(id) and is_binary(zone) and is_binary(uuid) and byte_size(uuid) == 36 and
             map_size(payload) == 3 do
    if match?({:ok, _}, Ecto.UUID.cast(uuid)),
      do: {:ok, payload},
      else: {:error, "invalid_payload"}
  end

  def args_from_command(1, _payload), do: {:error, "invalid_payload"}
  def args_from_command(_version, _payload), do: {:error, "unsupported_version"}

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}), do: run(Dawarich.Jobs.repo(), args)

  def run(repo, args, opts \\ []) do
    with {:ok, payload} <- args_from_command(1, Map.delete(args, "event_id")) do
      PreheatDigests.call(
        repo,
        payload["user_id"],
        Keyword.put(opts, :ambient_zone, payload["time_zone"])
      )
    end
  end
end

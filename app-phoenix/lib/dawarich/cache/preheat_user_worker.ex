defmodule Dawarich.Cache.PreheatUserWorker do
  @moduledoc false
  use Oban.Worker, queue: :projections, max_attempts: 3

  alias Dawarich.Cache.PreheatDigests
  alias Dawarich.Jobs.Processed

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
    event = args["event_id"]

    with {:ok, payload} <- args_from_command(1, Map.delete(args, "event_id")),
         true <- is_nil(event) or valid_event?(event) do
      if event && Processed.done?(repo, event),
        do: :ok,
        else: preheat(repo, payload, event, opts)
    else
      false -> {:error, "invalid_payload"}
      error -> error
    end
  rescue
    error -> {:error, error}
  end

  defp preheat(repo, payload, event, opts) do
    opts = Keyword.put(opts, :ambient_zone, payload["time_zone"])
    :ok = Dawarich.Cache.Readers.warm(repo, payload["user_id"], opts)

    :ok =
      PreheatDigests.call(
        repo,
        payload["user_id"],
        Keyword.put(opts, :ambient_zone, payload["time_zone"])
      )

    :ok = Dawarich.Cache.Readers.warm_digests(repo, payload["user_id"], opts)

    if hook = opts[:after_preheat], do: hook.()

    if event do
      case repo.transaction(fn -> Processed.claim!(repo, event, "cache.preheat_user") end) do
        {:ok, _} -> :ok
        error -> error
      end
    else
      :ok
    end
  end

  defp valid_event?(event) when is_binary(event) and byte_size(event) == 36,
    do: match?({:ok, _}, Ecto.UUID.cast(event))

  defp valid_event?(_event), do: false
end

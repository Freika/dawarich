defmodule Dawarich.Users.DestroyWorker do
  @moduledoc false
  use Oban.Worker,
    queue: :maintenance,
    priority: 0,
    max_attempts: 4,
    unique: [keys: [:event_id], states: :incomplete, period: :infinity]

  alias Dawarich.Jobs.{Ownership, Processed}
  alias Dawarich.Users.DestroyEffects

  def args_from_command(1, %{"user_id" => id} = payload)
      when map_size(payload) == 1 and is_integer(id) and id > 0 and
             id <= 9_223_372_036_854_775_807,
      do: {:ok, payload}

  def args_from_command(1, _), do: {:error, "invalid_payload"}
  def args_from_command(_, _), do: {:error, "unsupported_version"}

  def enqueue(repo, id, event \\ Ecto.UUID.generate()) do
    if repo.in_transaction?() do
      case Ownership.lock(repo, "command:users.destroy") do
        :oban ->
          repo.query!(
            "INSERT INTO public.job_outbox(event_id,command_type,command_version,payload,aggregate_id,metadata,scheduled_at) VALUES($1,'users.destroy',1,$2,$3,$4,now()) ON CONFLICT(event_id) DO NOTHING",
            [Ecto.UUID.dump!(event), %{"user_id" => id}, id, %{"producer" => "phoenix.users"}],
            log: false
          )

          :ok

        _ ->
          {:error, :worker_owner}
      end
    else
      {:error, :transaction_required}
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}), do: run(Dawarich.Jobs.repo(), args)

  def run(repo, args) do
    case Processed.once(repo, args["event_id"], "users.destroy", fn ->
           DestroyEffects.call(repo, args["user_id"])
         end) do
      {:error, {:cancel, reason}} ->
        {:cancel, reason}

      :ok ->
        if repo.query!("SELECT id FROM users WHERE id=$1", [args["user_id"]], log: false).rows ==
             [],
           do: DestroyEffects.clear_cache(args["user_id"])

        :ok

      result ->
        result
    end
  rescue
    error in Postgrex.Error -> {:error, {:cleanup, error.postgres[:code]}}
  end
end

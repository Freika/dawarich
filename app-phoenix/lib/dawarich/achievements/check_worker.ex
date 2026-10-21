defmodule Dawarich.Achievements.CheckWorker do
  @moduledoc false
  use Oban.Worker, queue: :projections, max_attempts: 25

  def args_from_command(
        1,
        %{"user_id" => id, "notify" => notify, "oldest_timestamp" => oldest} = payload
      )
      when is_integer(id) and is_boolean(notify) and (is_nil(oldest) or is_integer(oldest)) and
             map_size(payload) == 3,
      do: {:ok, %{"user_id" => id, "notify" => notify, "oldest_timestamp" => oldest}}

  def args_from_command(1, _payload), do: {:error, "invalid_payload"}
  def args_from_command(_version, _payload), do: {:error, "unsupported_version"}

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"user_id" => id, "notify" => notify, "oldest_timestamp" => oldest} = args
      }) do
    repo = Dawarich.Jobs.repo()

    case repo.transaction(fn ->
           outcome = Dawarich.Achievements.Checker.run(repo, id, notify, oldest)

           if outcome in [:ok, :missing] and args["event_id"],
             do:
               Dawarich.Jobs.Processed.mark!(
                 repo,
                 args["event_id"],
                 "achievements.check.completed"
               )

           outcome
         end) do
      {:ok, outcome} when outcome in [:ok, :missing] -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end

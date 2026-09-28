defmodule Dawarich.Achievements.CheckWorker do
  @moduledoc false
  use Oban.Worker, queue: :projections, max_attempts: 3

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
        args: %{"user_id" => id, "notify" => notify, "oldest_timestamp" => oldest}
      }) do
    case Dawarich.Achievements.Checker.run(Dawarich.Jobs.repo(), id, notify, oldest) do
      outcome when outcome in [:ok, :missing] -> :ok
    end
  end
end

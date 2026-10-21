defmodule Dawarich.Transportation.UserReclassifyWorker do
  @moduledoc false
  use Oban.Worker, queue: :tracks, max_attempts: 1

  def args_from_command(1, %{"user_id" => user} = payload)
      when is_integer(user) and map_size(payload) == 1,
      do: {:ok, payload}

  def args_from_command(1, _), do: {:error, "invalid_payload"}
  def args_from_command(_, _), do: {:error, "unsupported_version"}
  @impl Oban.Worker
  def perform(%Oban.Job{args: args}),
    do:
      Dawarich.Transportation.UserReclassify.run(Dawarich.Jobs.repo(), args, %{
        now: DateTime.utc_now()
      })
end

defmodule Dawarich.Posters.CreateWorker do
  @moduledoc false
  use Oban.Worker,
    queue: :posters,
    max_attempts: 2,
    unique: [keys: [:poster_id], states: :incomplete, period: :infinity]

  def args_from_command(1, %{"poster_id" => id, "user_id" => user, "locale" => locale} = payload)
      when is_integer(id) and id > 0 and is_integer(user) and user > 0 and
             locale in ~w(en de es fr pl ca zh) and map_size(payload) == 3,
      do: {:ok, payload}

  def args_from_command(1, _payload), do: {:error, "invalid_payload"}
  def args_from_command(_version, _payload), do: {:error, "unsupported_version"}

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"poster_id" => id, "user_id" => user, "event_id" => event, "locale" => locale}
      }) do
    case Dawarich.Posters.Generation.run(id, user, event, locale) do
      :ok -> :ok
      :lost -> {:cancel, "poster ownership or lease lost"}
      {:error, reason} -> {:error, reason}
    end
  end
end

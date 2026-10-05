defmodule Dawarich.Trips.WebRecalculate do
  @moduledoc false
  alias Dawarich.TripSettings
  alias Dawarich.Trips.{WebCommands, WebForm}

  def run(repo, user, id, context) do
    now = Map.get_lazy(context, :now, &DateTime.utc_now/0)

    if WebForm.active?(user, now) do
      repo.transaction(fn -> recalculate(repo, user, id, now) end)
      |> case do
        {:ok, result} -> result
        {:error, reason} -> {:error, reason}
      end
    else
      {:replay, "inactive trip recalculate"}
    end
  end

  defp recalculate(repo, user, id, now) do
    stamp = DateTime.to_naive(now)
    cutoff = NaiveDateTime.add(stamp, -60)

    case repo.query!(
           "SELECT last_recalculated_at IS NULL OR last_recalculated_at < $3 FROM trips WHERE id = $1 AND user_id = $2 FOR UPDATE",
           [id, user.id, cutoff],
           log: false
         ).rows do
      [[false]] ->
        {:ok, :cooldown}

      [[true]] ->
        with {:ok, settings} <- settings(user),
             :ok <- WebCommands.admission(repo) do
          repo.query!("UPDATE trips SET last_recalculated_at = $2 WHERE id = $1", [id, stamp],
            log: false
          )

          {:ok, _} = WebCommands.calculate!(repo, user, id, settings.unit, now)
          {:ok, :queued}
        end

      [] ->
        {:error, :not_found}
    end
  end

  defp settings(user) do
    case TripSettings.read(user.settings) do
      {:ok, settings} -> {:ok, settings}
      :rails -> {:replay, "trip recalculate settings"}
    end
  end
end

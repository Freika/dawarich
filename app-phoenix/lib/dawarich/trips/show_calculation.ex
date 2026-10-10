defmodule Dawarich.Trips.ShowCalculation do
  @moduledoc false
  alias Dawarich.TripPage
  alias Dawarich.Trips.WebCommands
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  def admitted?(repo, user, id, now) do
    with {:ok, state} <- state(repo, user, id, now) do
      not state.needed or
        repo.query!(
          "SELECT owner FROM phoenix.job_owners WHERE key = 'command:trips.calculate'",
          [],
          log: false
        ).rows == [["oban"]]
    else
      _ -> false
    end
  end

  def run(repo, user, id, context) do
    if context[:connected] do
      {:ok, :connected}
    else
      now = Map.get_lazy(context, :now, &DateTime.utc_now/0)

      repo.transaction(fn ->
        repo.query!("SELECT id FROM trips WHERE id=$1 AND user_id=$2 FOR UPDATE", [id, user.id],
          log: false
        )

        with {:ok, state} <- state(repo, user, id, now) do
          cond do
            state.needed -> WebCommands.calculate!(repo, user, id, state.unit, now)
            true -> {:ok, :ready}
          end
        end
      end)
      |> case do
        {:ok, result} -> result
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp state(repo, user, id, now) do
    with {:ok, gated} <- TripPage.gate(user, id),
         [[path_blank, distance, countries, started, source]] <-
           repo.query!(
             "SELECT path IS NULL OR ST_IsEmpty(path), distance, visited_countries, started_at, source_identifier FROM trips WHERE id=$1 AND user_id=$2",
             [id, user.id],
             log: false
           ).rows do
      future =
        Ruby.present?(source) and NaiveDateTime.compare(started, DateTime.to_naive(now)) == :gt

      needed = not future and (path_blank or Ruby.blank?(distance) or Ruby.blank?(countries))
      {:ok, %{needed: needed, unit: gated.settings.unit}}
    else
      _ -> {:replay, "trip show calculation state"}
    end
  end
end

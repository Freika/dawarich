defmodule Dawarich.Trips.WebDelete do
  @moduledoc false

  @planned ~w(planned_reservations planned_accommodations planned_travellers planned_unplanned_places)

  def run(repo, user, id, _context) do
    repo.transaction(fn ->
      case repo.query!(
             "SELECT id FROM trips WHERE id = $1 AND user_id = $2 FOR UPDATE",
             [id, user.id],
             log: false
           ).rows do
        [[^id]] ->
          case Dawarich.Trips.PlanRead.supported?(repo, user.id, id) do
            true ->
              delete(repo, id)
              {:ok, :deleted}

            false ->
              {:replay, "trip dependent rich content"}
          end

        [] ->
          {:error, :not_found}
      end
    end)
    |> case do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  defp delete(repo, id) do
    rich_ids =
      repo.query!(
        "SELECT id FROM action_text_rich_texts WHERE record_type='Trip' AND record_id=$1 AND name='description' ORDER BY id FOR UPDATE",
        [id],
        log: false
      ).rows
      |> Enum.map(&hd/1)

    Dawarich.Trips.Attachments.detach!(repo, rich_ids)

    days =
      repo.query!("SELECT id FROM planned_days WHERE trip_id = $1 FOR UPDATE", [id], log: false).rows
      |> Enum.map(&hd/1)

    repo.query!(
      "UPDATE planned_reservations SET planned_day_id = NULL WHERE planned_day_id = ANY($1::bigint[])",
      [days],
      log: false
    )

    repo.query!("DELETE FROM planned_day_notes WHERE planned_day_id = ANY($1::bigint[])", [days],
      log: false
    )

    repo.query!("DELETE FROM planned_stops WHERE planned_day_id = ANY($1::bigint[])", [days],
      log: false
    )

    repo.query!("DELETE FROM planned_days WHERE trip_id = $1", [id], log: false)

    for table <- @planned,
        do: repo.query!("DELETE FROM #{table} WHERE trip_id = $1", [id], log: false)

    repo.query!("DELETE FROM notes WHERE attachable_type = 'Trip' AND attachable_id = $1", [id],
      log: false
    )

    repo.query!(
      "DELETE FROM action_text_rich_texts WHERE record_type = 'Trip' AND record_id = $1 AND name = 'description'",
      [id],
      log: false
    )

    repo.query!("DELETE FROM shared_links WHERE resource_type = 0 AND resource_id = $1", [id],
      log: false
    )

    repo.query!("DELETE FROM trips WHERE id = $1", [id], log: false)
  end
end

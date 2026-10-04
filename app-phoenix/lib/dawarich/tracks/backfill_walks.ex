defmodule Dawarich.Tracks.BackfillWalks do
  @moduledoc false

  alias Dawarich.Jobs.Ownership

  @active 43_200
  @backoff 604_800
  @columns ~w(user_id walk_id cursor_timestamp step_event_id selected_start_timestamp selected_end_timestamp state expires_at time_zone)a
  @returning "user_id, walk_id::text, cursor_timestamp, step_event_id::text, selected_start_timestamp, selected_end_timestamp, state, expires_at, time_zone"

  def schedule(repo, user_id, zone, now, publish) do
    transaction(repo, fn ->
      values =
        repo.query!(
          """
          INSERT INTO phoenix.track_backfill_walks AS stored
            (user_id, walk_id, state, expires_at, time_zone, inserted_at, updated_at)
          VALUES ($1, $2, 'walking', $4, $5, $3, $3)
          ON CONFLICT (user_id) DO UPDATE SET walk_id = EXCLUDED.walk_id,
            cursor_timestamp = NULL, step_event_id = NULL, selected_start_timestamp = NULL,
            selected_end_timestamp = NULL, state = 'walking', expires_at = EXCLUDED.expires_at,
            time_zone = EXCLUDED.time_zone, inserted_at = EXCLUDED.inserted_at, updated_at = EXCLUDED.updated_at
          WHERE stored.expires_at <= $3
          RETURNING #{@returning}
          """,
          [user_id, Ecto.UUID.dump!(Ecto.UUID.generate()), now, DateTime.add(now, @active), zone],
          log: false
        ).rows

      case values do
        [values] ->
          walk = row(values) |> Map.put(:due_at, now)
          publish!(repo, publish, walk)
          {:inserted, walk}

        [] ->
          :occupied
      end
    end)
  end

  def select(repo, user_id, walk_id, cursor, choose) do
    transaction(repo, fn ->
      case current(repo, user_id, walk_id, cursor) do
        nil -> :stale
        %{step_event_id: step} = walk when not is_nil(step) -> {:selected, walk}
        walk -> select_range(repo, walk, choose.())
      end
    end)
  end

  def advance(repo, step, now, publish) do
    transaction(repo, fn ->
      case current(repo, step.user_id, step.walk_id, step.cursor_timestamp) do
        %{step_event_id: event} when event == step.step_event_id and not is_nil(event) ->
          [values] =
            repo.query!(
              "UPDATE phoenix.track_backfill_walks SET cursor_timestamp = selected_start_timestamp, " <>
                "step_event_id = NULL, selected_start_timestamp = NULL, selected_end_timestamp = NULL, " <>
                "expires_at = $3, updated_at = $4 WHERE user_id = $1 AND walk_id = $2 RETURNING #{@returning}",
              [step.user_id, Ecto.UUID.dump!(step.walk_id), DateTime.add(now, @active), now],
              log: false
            ).rows

          next =
            row(values)
            |> Map.merge(%{due_at: DateTime.add(now, 60), event_id: step.step_event_id})

          publish!(repo, publish, next)
          {:advanced, next}

        _ ->
          :stale
      end
    end)
  end

  def finish(repo, user_id, walk_id, cursor, now) do
    transaction(repo, fn ->
      case current(repo, user_id, walk_id, cursor) do
        nil ->
          :stale

        _ ->
          repo.query!(
            "UPDATE phoenix.track_backfill_walks SET state = 'backoff', step_event_id = NULL, " <>
              "selected_start_timestamp = NULL, selected_end_timestamp = NULL, expires_at = $3, " <>
              "updated_at = $4 WHERE user_id = $1 AND walk_id = $2",
            [user_id, Ecto.UUID.dump!(walk_id), DateTime.add(now, @backoff), now],
            log: false
          )

          :backoff
      end
    end)
  end

  def release(repo, user_id, walk_id) do
    transaction(repo, fn ->
      case repo.query!(
             "DELETE FROM phoenix.track_backfill_walks WHERE user_id = $1 AND walk_id = $2 RETURNING user_id",
             [user_id, Ecto.UUID.dump!(walk_id)],
             log: false
           ).num_rows do
        0 -> :stale
        _ -> :released
      end
    end)
  end

  def current(repo, user_id, walk_id, cursor) do
    case repo.query!(
           "SELECT #{@returning} FROM phoenix.track_backfill_walks WHERE user_id = $1 AND walk_id = $2 " <>
             "AND cursor_timestamp IS NOT DISTINCT FROM $3::bigint AND state = 'walking' FOR UPDATE",
           [user_id, Ecto.UUID.dump!(walk_id), cursor],
           log: false
         ).rows do
      [values] -> row(values)
      [] -> nil
    end
  end

  defp select_range(_repo, walk, nil), do: {:empty, walk}

  defp select_range(repo, walk, {from, until}) do
    [values] =
      repo.query!(
        "UPDATE phoenix.track_backfill_walks SET step_event_id = $3, selected_start_timestamp = $4, " <>
          "selected_end_timestamp = $5 WHERE user_id = $1 AND walk_id = $2 RETURNING #{@returning}",
        [
          walk.user_id,
          Ecto.UUID.dump!(walk.walk_id),
          Ecto.UUID.dump!(Ecto.UUID.generate()),
          from,
          until
        ],
        log: false
      ).rows

    {:selected, row(values)}
  end

  defp transaction(repo, fun) do
    repo.transaction(fn ->
      Ownership.lock(repo, "command:tracks.throttled_backfill")
      fun.()
    end)
  end

  defp publish!(repo, publish, walk) do
    case publish.(walk) do
      {:error, reason} -> repo.rollback(reason)
      _ -> :ok
    end
  end

  defp row(values), do: Map.new(Enum.zip(@columns, values))
end

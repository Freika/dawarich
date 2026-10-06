defmodule Dawarich.Points.WebDestroy do
  @moduledoc false
  alias Dawarich.RubyInteger
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  def run(repo, user, ids, ctx) do
    ids = ids || []

    if is_list(ids) and Enum.all?(ids, &is_binary/1) do
      selected = Enum.any?(ids, &(not Ruby.blank?(&1)))

      ids =
        ids
        |> Enum.reject(&Ruby.blank?/1)
        |> Enum.map(&RubyInteger.to_i/1)
        |> Enum.filter(&(&1 >= 0 and &1 <= 9_223_372_036_854_775_807))
        |> Enum.uniq()

      case repo.transaction(fn ->
             repo.query!("SELECT id FROM users WHERE id=$1 FOR UPDATE", [user.id])

             rows =
               repo.query!(
                 "WITH deleted AS (DELETE FROM points WHERE user_id=$1 AND id=ANY($2::bigint[]) " <>
                   "RETURNING id,timestamp,track_id,import_id) " <>
                   "SELECT id,timestamp,track_id,import_id FROM deleted ORDER BY id ASC",
                 [user.id, ids]
               ).rows

             deleted =
               Enum.map(rows, fn [id, timestamp, track_id, import_id] ->
                 %{id: id, timestamp: timestamp, track_id: track_id, import_id: import_id}
               end)

             counters(repo, user.id, deleted)
             follow_up(repo, user, deleted, ctx)
             render(repo, {:ok, %{deleted: deleted, selected: selected}}, ctx)
           end) do
        {:ok, result} -> result
        {:error, :rails} -> :rails
      end
    else
      :rails
    end
  rescue
    _ -> :rails
  end

  defp counters(_repo, _user, []), do: :ok

  defp counters(repo, user_id, deleted) do
    repo.query!("UPDATE users SET points_count=COALESCE(points_count,0)-$2 WHERE id=$1", [
      user_id,
      length(deleted)
    ])

    deleted
    |> Enum.reject(&is_nil(&1.import_id))
    |> Enum.frequencies_by(& &1.import_id)
    |> Enum.sort()
    |> Enum.each(fn {id, count} ->
      repo.query!("UPDATE imports SET points_count=COALESCE(points_count,0)-$2 WHERE id=$1", [
        id,
        count
      ])
    end)
  end

  defp follow_up(_repo, _user, [], _ctx), do: :ok

  defp follow_up(repo, user, deleted, ctx),
    do: Dawarich.Points.WebDestroyEffects.publish!(repo, user, deleted, ctx)

  defp render(repo, {:ok, result} = outcome, ctx) do
    case Map.get(ctx, :render) do
      nil ->
        outcome

      fun ->
        case fun.(outcome) do
          {:ok, response} -> {:ok, Map.put(result, :response, response)}
          :rails -> repo.rollback(:rails)
        end
    end
  end
end

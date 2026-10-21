defmodule Dawarich.UserData.Restore.Digests do
  @moduledoc false
  alias Dawarich.UserData.Restore.Batch
  alias Dawarich.Ingest.Ruby

  def call(repo, user, data, context) when is_list(data) do
    Enum.reduce(data, 0, fn row, count -> count + restore(repo, user, row, context) end)
  end

  def call(_, _, _, _), do: 0

  defp restore(repo, user, row, context) when is_map(row) do
    attrs =
      row
      |> Map.delete("sharing_uuid")
      |> Map.put("user_id", user)
      |> Map.put("sharing_uuid", Ecto.UUID.generate())

    attrs =
      Enum.reduce(~w(created_at updated_at), attrs, fn key, acc ->
        if Ruby.blank?(acc[key]), do: Map.put(acc, key, context.now), else: acc
      end)

    cast = Batch.row!(repo, "digests", attrs, context)
    year = cast["year"]
    month = cast["month"]
    period = cast["period_type"] || 0

    cond do
      is_nil(year) or (period == 0 and is_nil(month)) or (month != nil and month not in 1..12) ->
        0

      repo.query!(
        "SELECT id FROM digests WHERE user_id=$1 AND year=$2 AND month IS NOT DISTINCT FROM $3 AND period_type=$4 LIMIT 1",
        [user, year, month, period],
        log: false
      ).rows != [] ->
        0

      true ->
        Batch.create!(repo, "digests", attrs, context)
    end
  end

  defp restore(_, _, _, _), do: 0
end

defmodule Dawarich.RawData.Clearer do
  @moduledoc false

  require Logger

  @batch 10_000
  @all """
  SELECT a.id FROM points_raw_data_archives a
  WHERE a.verified_at IS NOT NULL
    AND ($1::integer IS NULL OR a.verified_at <= now() - make_interval(days => $1::integer))
    AND EXISTS (SELECT 1 FROM points p WHERE p.raw_data_archive_id = a.id
                AND p.raw_data_archived = true AND p.raw_data <> '{}'::jsonb)
  ORDER BY a.id
  """
  @month """
  SELECT id FROM points_raw_data_archives
  WHERE user_id = $1 AND year = $2 AND month = $3 AND verified_at IS NOT NULL ORDER BY chunk_number
  """
  @points """
  SELECT id FROM points
  WHERE raw_data_archive_id = $1 AND raw_data_archived = true AND raw_data <> '{}'::jsonb ORDER BY id
  """
  @clear "UPDATE points SET raw_data = '{}'::jsonb WHERE id = ANY($1) AND raw_data_archived = true"

  def clear_all(repo, cooling_days), do: clear(repo, ids(repo, @all, [cooling_days]))

  def clear_month(repo, user_id, year, month),
    do: clear(repo, ids(repo, @month, [user_id, year, month]))

  defp clear(repo, archive_ids), do: Enum.reduce(archive_ids, 0, &(&2 + clear_archive(repo, &1)))

  defp clear_archive(repo, archive_id) do
    repo
    |> ids(@points, [archive_id])
    |> Enum.chunk_every(@batch)
    |> Enum.reduce(0, fn batch, total ->
      total + repo.query!(@clear, [batch], log: false).num_rows
    end)
  rescue
    error in [Postgrex.Error, DBConnection.ConnectionError] ->
      Logger.error("✗ Failed to clear archive #{archive_id}: #{Exception.message(error)}")
      0
  end

  defp ids(repo, sql, params), do: repo.query!(sql, params, log: false).rows |> List.flatten()
end

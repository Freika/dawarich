defmodule Dawarich.Tracks.Destroy do
  @moduledoc false

  alias Dawarich.Tracks.{Effects, Sql}

  @clean_sql """
  SELECT t.id FROM tracks t
  WHERE t.user_id = $1 AND NOT #{Sql.kept("t")}
    AND (($2::bigint IS NULL AND $3::bigint IS NULL) OR (t.start_at, t.end_at) OVERLAPS
      (to_timestamp($2::bigint) AT TIME ZONE 'UTC', to_timestamp($3::bigint) AT TIME ZONE 'UTC'))
  ORDER BY t.id
  """

  def destroy!(_repo, _user_id, []), do: []

  def destroy!(repo, user_id, ids) do
    {:ok, rows} =
      repo.transaction(fn ->
        repo.query!("UPDATE points SET track_id = NULL WHERE track_id = ANY($1::bigint[])", [ids],
          log: false
        )

        repo.query!("DELETE FROM track_segments WHERE track_id = ANY($1::bigint[])", [ids],
          log: false
        )

        repo.query!(
          "DELETE FROM shared_links WHERE resource_type = 1 AND resource_id = ANY($1::bigint[])",
          [ids],
          log: false
        )

        rows =
          repo.query!(
            "DELETE FROM tracks WHERE id = ANY($1::bigint[]) " <>
              "RETURNING id, floor(extract(epoch FROM start_at))::bigint, floor(extract(epoch FROM end_at))::bigint",
            [ids],
            log: false
          ).rows
          |> Enum.map(&List.to_tuple/1)
          |> Enum.sort()

        Effects.write!(repo, user_id, %{
          destroyed: Enum.map(rows, &elem(&1, 0)),
          stamps: Enum.flat_map(rows, fn {_, start_at, end_at} -> [start_at, end_at] end)
        })

        rows
      end)

    rows
  end

  def clean_range!(_repo, _user_id, start_ts, end_ts)
      when is_integer(start_ts) and is_integer(end_ts) and start_ts > end_ts,
      do: []

  def clean_range!(repo, user_id, start_ts, end_ts) do
    ids = repo.query!(@clean_sql, [user_id, start_ts, end_ts], log: false).rows |> List.flatten()
    destroy!(repo, user_id, ids)
  end
end

defmodule Dawarich.Stats.GeocodedDays do
  @moduledoc false

  @delay 3_600
  @mark """
  INSERT INTO phoenix.stats_geocoded_days (member, version, due_at) VALUES ($1, $2, $3)
  ON CONFLICT (member) DO UPDATE SET version = EXCLUDED.version
  """
  @due """
  SELECT member, version FROM phoenix.stats_geocoded_days WHERE due_at <= $1
  ORDER BY due_at, member COLLATE "C" LIMIT $2
  """
  @snapshot "SELECT member, version FROM phoenix.stats_geocoded_days WHERE member = ANY($1::text[])"
  @acknowledge """
  WITH gone AS (
    DELETE FROM phoenix.stats_geocoded_days WHERE member = $1 AND version = $2 RETURNING 1
  )
  UPDATE phoenix.stats_geocoded_days SET due_at = $3 WHERE member = $1 AND NOT EXISTS (SELECT 1 FROM gone)
  """
  @postpone "UPDATE phoenix.stats_geocoded_days SET due_at = $2 WHERE member = $1"
  @interior """
  WITH b AS (
    SELECT make_timestamp($2, $3, 1, 0, 0, 0) AT TIME ZONE $1 AS first,
      (make_timestamp($2, $3, 1, 0, 0, 0) + interval '1 month') AT TIME ZONE $1 AS last
  )
  SELECT to_char(d, 'YYYY-MM-DD') FROM b,
    generate_series((b.first AT TIME ZONE 'UTC')::date::timestamp,
      (b.last AT TIME ZONE 'UTC')::date::timestamp, interval '1 day') AS d
  WHERE d AT TIME ZONE 'UTC' >= b.first AND (d + interval '1 day') AT TIME ZONE 'UTC' <= b.last
  ORDER BY d
  """
  @local_months """
  SELECT extract(year FROM to_timestamp(t) AT TIME ZONE $1)::int,
    extract(month FROM to_timestamp(t) AT TIME ZONE $1)::int
  FROM unnest(ARRAY[$2::bigint, $3::bigint]) WITH ORDINALITY AS u(t, o) ORDER BY o
  """

  def mark(repo, user_id, timestamp, now \\ System.os_time(:second)) do
    repo.query!(@mark, [member(user_id, timestamp), Ecto.UUID.generate(), now + @delay],
      log: false
    )

    :ok
  end

  def due(repo, limit, now \\ System.os_time(:second)),
    do: tuples(repo.query!(@due, [now, limit], log: false).rows)

  def snapshot_month(repo, user_id, zone, year, month) do
    members =
      for [day] <- repo.query!(@interior, [zone, year, month], log: false).rows,
          do: "#{user_id}:#{day}"

    tuples(repo.query!(@snapshot, [members], log: false).rows)
  end

  def acknowledge(repo, entries, now \\ System.os_time(:second)) do
    Enum.each(entries, fn {member, version} ->
      repo.query!(@acknowledge, [member, version, now + @delay], log: false)
    end)
  end

  def postpone(repo, member, now \\ System.os_time(:second)) do
    repo.query!(@postpone, [member, now + @delay], log: false)
    :ok
  end

  def local_months(repo, member, zone) do
    [_user, day] = String.split(member, ":", parts: 2)
    start = day |> Date.from_iso8601!() |> DateTime.new!(~T[00:00:00]) |> DateTime.to_unix()

    repo.query!(@local_months, [zone, start, start + 86_399], log: false).rows
    |> tuples()
    |> Enum.uniq()
  end

  defp member(user_id, timestamp),
    do:
      "#{user_id}:#{timestamp |> DateTime.from_unix!() |> DateTime.to_date() |> Date.to_iso8601()}"

  defp tuples(rows), do: Enum.map(rows, &List.to_tuple/1)
end

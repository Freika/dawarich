defmodule Dawarich.Stats.RefreshToponyms do
  @moduledoc false

  alias Dawarich.Stats.{MonthQueries, ToponymRuns}

  @bounds """
  SELECT extract(epoch FROM make_timestamp($2, $3, 1, 0, 0, 0) AT TIME ZONE $1)::bigint,
    extract(epoch FROM (make_timestamp($2, $3, 1, 0, 0, 0) + interval '1 month') AT TIME ZONE $1)::bigint
  """
  @lock "SELECT id FROM stats WHERE user_id = $1 AND year = $2 AND month = $3 ORDER BY id LIMIT 1 FOR UPDATE"
  @exists """
  SELECT EXISTS (SELECT 1 FROM points
    WHERE user_id = $1 AND (anomaly = FALSE OR anomaly IS NULL) AND timestamp >= $2 AND timestamp < $3)
  """
  @points """
  SELECT id, timestamp, city, country_name, country_id, velocity FROM points
  WHERE user_id = $1 AND (anomaly = FALSE OR anomaly IS NULL) AND timestamp >= $2 AND timestamp < $3
  ORDER BY timestamp, id
  """
  @distinct "SELECT toponyms IS DISTINCT FROM $2::jsonb FROM stats WHERE id = $1"
  @watermark """
  UPDATE users SET stats_swept_at = (SELECT max(updated_at) FROM stats WHERE user_id = $1)
  WHERE id = $1 AND stats_swept_at IS NULL AND deleted_at IS NULL
  """
  @write "UPDATE stats SET toponyms = $2, updated_at = $3 WHERE id = $1"

  def call(repo, account, year, month, invalidate, opts \\ []) do
    now = Keyword.get_lazy(opts, :now, &NaiveDateTime.utc_now/0)

    {:ok, result} =
      repo.transaction(fn -> refresh(repo, account, year, month, invalidate, now) end)

    result
  end

  defp refresh(repo, account, year, month, invalidate, now) do
    [[first, next]] = repo.query!(@bounds, [account.zone, year, month], log: false).rows

    case repo.query!(@lock, [account.id, year, month], log: false).rows do
      [] ->
        [[found]] = repo.query!(@exists, [account.id, first, next], log: false).rows
        not found

      [[id]] ->
        runs = ToponymRuns.new(MonthQueries.country_names(repo), account.min_minutes)

        value =
          repo
          |> MonthQueries.fold(@points, [account.id, first, next], runs)
          |> ToponymRuns.result()

        [[changed]] = repo.query!(@distinct, [id, value], log: false).rows

        if changed do
          repo.query!(@watermark, [account.id], log: false)
          repo.query!(@write, [id, value, now], log: false)
        end

        if changed or invalidate,
          do:
            Dawarich.Stats.CacheInvalidation.call(
              repo,
              %{
                "user_id" => account.id,
                "year" => year,
                "scope" => "toponyms"
              }
            )

        true
    end
  end
end

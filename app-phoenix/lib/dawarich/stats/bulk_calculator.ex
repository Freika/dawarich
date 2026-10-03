defmodule Dawarich.Stats.BulkCalculator do
  @moduledoc false

  alias Dawarich.Stats.{Accounts, Schedule}

  @version 3
  @stale_per_run 5
  @jitter 3_300
  @overlap 300
  @watermark """
  SELECT COALESCE(stats_swept_at, (SELECT max(updated_at) FROM stats WHERE stats.user_id = users.id))
  FROM users WHERE id = $1 AND deleted_at IS NULL
  """
  @months_by_timestamp """
  SELECT DISTINCT EXTRACT(YEAR FROM to_timestamp(timestamp) AT TIME ZONE $1)::int,
    EXTRACT(MONTH FROM to_timestamp(timestamp) AT TIME ZONE $1)::int
  FROM points WHERE user_id = $2 AND timestamp BETWEEN $3::bigint AND $4::bigint ORDER BY 1, 2
  """
  @months_by_created """
  SELECT DISTINCT EXTRACT(YEAR FROM to_timestamp(timestamp) AT TIME ZONE $1)::int,
    EXTRACT(MONTH FROM to_timestamp(timestamp) AT TIME ZONE $1)::int
  FROM points WHERE user_id = $2 AND created_at BETWEEN $3 AND $4 ORDER BY 1, 2
  """
  @stale """
  SELECT year, month FROM stats WHERE user_id = $1 AND calculation_version < #{@version}
  ORDER BY repair_deferred_at ASC NULLS FIRST, id LIMIT #{@stale_per_run}
  """
  @defer "UPDATE stats SET repair_deferred_at = $4 WHERE user_id = $1 AND year = $2 AND month = $3"
  @swept "UPDATE users SET stats_swept_at = $2 WHERE id = $1"

  def call(repo, user_id, opts \\ []) do
    now = Keyword.get_lazy(opts, :now, &NaiveDateTime.utc_now/0)

    account =
      Accounts.find(repo, user_id) ||
        raise(ArgumentError, "Couldn't find User with 'id'=#{user_id}")

    {:ok, :ok} = repo.transaction(fn -> sweep(repo, account, now, opts) end)
    :ok
  end

  defp sweep(repo, account, now, opts) do
    new = months(repo, account, now)

    Enum.each(new, fn [year, month] ->
      Schedule.calculate(repo, account.id, year, month, true, opts)
    end)

    repairs = rows(repo, @stale, [account.id]) -- new

    Enum.each(repairs, fn [year, month] ->
      Schedule.calculate(
        repo,
        account.id,
        year,
        month,
        false,
        Keyword.put(opts, :schedule_in, jitter(opts))
      )
    end)

    Enum.each(repairs, fn [year, month] ->
      repo.query!(@defer, [account.id, year, month, now], log: false)
    end)

    repo.query!(@swept, [account.id, now], log: false)
    :ok
  end

  defp months(repo, %{swept_at: nil} = account, now) do
    from =
      case rows(repo, @watermark, [account.id]) do
        [[nil]] -> 0
        [[at]] -> epoch(at)
      end

    rows(repo, @months_by_timestamp, [account.zone, account.id, from, epoch(now)])
  end

  defp months(repo, account, now),
    do:
      rows(repo, @months_by_created, [
        account.zone,
        account.id,
        NaiveDateTime.add(account.swept_at, -@overlap),
        now
      ])

  defp jitter(opts), do: Keyword.get(opts, :jitter, fn -> :rand.uniform(@jitter + 1) - 1 end).()
  defp epoch(at), do: at |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix()
  defp rows(repo, sql, params), do: repo.query!(sql, params, log: false).rows
end

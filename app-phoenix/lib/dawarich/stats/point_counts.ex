defmodule Dawarich.Stats.PointCounts do
  @moduledoc false

  alias Dawarich.{Jobs, Repo}

  @ttl 86_400
  @without_data " AND city IS NULL AND country_name IS NULL AND country IS NULL AND country_id IS NULL"

  def fetch(user_id, store_geodata, now, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)

    cache_repo =
      Keyword.get_lazy(opts, :cache_repo, fn -> if opts[:repo], do: repo, else: Jobs.repo() end)

    generation = Dawarich.AfterCommit.Visibility.generation(repo, user_id)

    case cached(cache_repo, user_id, now, generation) do
      nil ->
        tap(
          compute(repo, user_id, store_geodata),
          &store(cache_repo, user_id, &1, now, generation)
        )

      counts ->
        counts
    end
  end

  defp cached(cache_repo, user_id, now, generation) do
    case cache_repo.query!(
           "SELECT geocoded, without_data FROM phoenix.stats_point_counts WHERE user_id = $1 AND computed_at > $2 AND COALESCE((SELECT value FROM phoenix.cursors WHERE key=$3),'')=$4",
           [user_id, DateTime.add(now, -@ttl), "stats_point_counts:#{user_id}", generation],
           log: false
         ) do
      %{rows: [[geocoded, without_data]]} -> %{geocoded: geocoded, without_data: without_data}
      _ -> nil
    end
  end

  defp compute(repo, user_id, store_geodata),
    do: %{
      geocoded: count(repo, user_id, ""),
      without_data: if(store_geodata, do: count(repo, user_id, @without_data))
    }

  defp count(repo, user_id, extra) do
    %{rows: [[count]]} =
      repo.query!(
        "SELECT count(*) FROM points WHERE user_id = $1 AND reverse_geocoded_at IS NOT NULL" <>
          extra,
        [user_id]
      )

    count
  end

  defp store(cache_repo, user_id, counts, now, generation) do
    cache_repo.transaction(fn ->
      cache_repo.query!(
        """
        INSERT INTO phoenix.stats_point_counts (user_id, geocoded, without_data, computed_at)
        VALUES ($1, $2, $3, $4)
        ON CONFLICT (user_id) DO UPDATE
        SET geocoded = EXCLUDED.geocoded, without_data = EXCLUDED.without_data, computed_at = EXCLUDED.computed_at
        """,
        [user_id, counts.geocoded, counts.without_data, now],
        log: false
      )

      Dawarich.State.put_cursor(cache_repo, "stats_point_counts:#{user_id}", generation)
    end)
  end
end

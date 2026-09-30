defmodule Dawarich.Stats.PointCounts do
  @moduledoc false

  alias Dawarich.{Jobs, Repo}

  @ttl 86_400
  @without_data " AND city IS NULL AND country_name IS NULL AND country IS NULL AND country_id IS NULL"

  def fetch(user_id, store_geodata, now) do
    case cached(user_id, now) do
      nil -> tap(compute(user_id, store_geodata), &store(user_id, &1, now))
      counts -> counts
    end
  end

  defp cached(user_id, now) do
    case Jobs.repo().query!(
           "SELECT geocoded, without_data FROM phoenix.stats_point_counts WHERE user_id = $1 AND computed_at > $2",
           [user_id, DateTime.add(now, -@ttl)],
           log: false
         ) do
      %{rows: [[geocoded, without_data]]} -> %{geocoded: geocoded, without_data: without_data}
      _ -> nil
    end
  end

  defp compute(user_id, store_geodata),
    do: %{
      geocoded: count(user_id, ""),
      without_data: if(store_geodata, do: count(user_id, @without_data))
    }

  defp count(user_id, extra) do
    %{rows: [[count]]} =
      Repo.query!(
        "SELECT count(*) FROM points WHERE user_id = $1 AND reverse_geocoded_at IS NOT NULL" <>
          extra,
        [user_id]
      )

    count
  end

  defp store(user_id, counts, now),
    do:
      Jobs.repo().query!(
        """
        INSERT INTO phoenix.stats_point_counts (user_id, geocoded, without_data, computed_at)
        VALUES ($1, $2, $3, $4)
        ON CONFLICT (user_id) DO UPDATE
        SET geocoded = EXCLUDED.geocoded, without_data = EXCLUDED.without_data, computed_at = EXCLUDED.computed_at
        """,
        [user_id, counts.geocoded, counts.without_data, now],
        log: false
      )
end

defmodule Dawarich.Digests.Refresh.Activity do
  @moduledoc false
  alias Dawarich.Geo
  @modes ~w(unknown stationary walking running cycling driving bus train flying boat motorcycle)

  def fetch(context, first, last), do: context |> fetch_pairs(first, last) |> Map.new()

  def fetch_pairs(context, first, last) do
    repo = context.repo

    rows =
      repo.query!(
        """
        SELECT s.transportation_mode,COALESCE(SUM(s.duration),0)
        FROM track_segments s JOIN tracks t ON t.id=s.track_id
        WHERE t.user_id=$1 AND t.start_at BETWEEN $2 AND $3 GROUP BY s.transportation_mode
        """,
        [context.id, first, last]
      ).rows

    durations =
      Enum.map(rows, fn [mode, n] -> {if(mode in 0..10, do: Enum.at(@modes, mode)), n} end)

    tracks =
      repo.query!(
        "SELECT id,start_at,end_at FROM tracks WHERE user_id=$1 AND start_at BETWEEN $2 AND $3 ORDER BY start_at",
        [context.id, first, last]
      ).rows

    gaps = gaps(tracks, repo)

    durations =
      Enum.reduce(gaps, durations, fn {mode, seconds}, acc ->
        if seconds > 0 do
          case List.keyfind(acc, mode, 0) do
            nil -> acc ++ [{mode, seconds}]
            {^mode, existing} -> List.keyreplace(acc, mode, 0, {mode, existing + seconds})
          end
        else
          acc
        end
      end)

    total = Enum.sum(Enum.map(durations, &elem(&1, 1)))

    if total == 0,
      do: [],
      else:
        for(
          {mode, n} <- durations,
          mode != nil,
          do: {mode, %{"duration" => trunc(n), "percentage" => round(n / total * 100)}}
        )
  end

  def classify(seconds, distance_km) do
    cond do
      seconds <= 0 ->
        {0, 0}

      seconds <= 86400 and distance_km * 1000 <= 100 ->
        {seconds, 0}

      seconds <= 86400 and distance_km >= 100 and distance_km / (seconds / 3600.0) >= 150 ->
        {0, seconds}

      true ->
        {0, 0}
    end
  end

  defp gaps(tracks, _repo) when length(tracks) < 2, do: [{"stationary", 0}, {"flying", 0}]

  defp gaps(tracks, repo) do
    ids = Enum.map(tracks, &hd/1)
    first = boundary(repo, ids, "ASC")
    last = boundary(repo, ids, "DESC")

    {stationary, flying} =
      tracks
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.reduce({0, 0}, fn
        [[id, _start, ending], [next_id, starting, _end]], {stationary, flying} ->
          gap = unix(starting) - unix(ending)

          {s, f} =
            if gap > 0 and Map.has_key?(last, id) and Map.has_key?(first, next_id),
              do: classify(gap, Geo.distance_m(last[id], first[next_id]) / 1000),
              else: {0, 0}

          {stationary + s, flying + f}
      end)

    [{"stationary", stationary}, {"flying", flying}]
  end

  defp boundary(repo, ids, direction) do
    rows =
      repo.query!(
        "SELECT DISTINCT ON(track_id) track_id,ST_Y(lonlat::geometry),ST_X(lonlat::geometry) FROM points WHERE track_id=ANY($1) ORDER BY track_id,timestamp #{direction}",
        [ids]
      ).rows

    Map.new(rows, fn [id, lat, lon] -> {id, {lat, lon}} end)
  end

  defp unix(time), do: time |> NaiveDateTime.diff(~N[1970-01-01 00:00:00], :second)
end

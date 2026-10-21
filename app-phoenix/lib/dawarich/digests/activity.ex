defmodule Dawarich.Digests.Activity do
  @moduledoc false

  @modes ~w(unknown stationary walking running cycling driving bus train flying boat motorcycle)

  def calculate(repo, context, period) do
    params = [context.user_id, period.from, period.until]

    values =
      repo.query!(
        "SELECT s.transportation_mode, coalesce(sum(s.duration), 0)::bigint " <>
          "FROM public.track_segments s JOIN public.tracks t ON t.id = s.track_id " <>
          "WHERE t.user_id = $1 AND t.start_at >= $2 AND t.start_at <= $3 " <>
          "GROUP BY s.transportation_mode ORDER BY s.transportation_mode",
        params,
        log: false
      ).rows
      |> Map.new(fn [mode, duration] ->
        {if(mode in 0..10, do: Enum.at(@modes, mode)), duration}
      end)

    tracks =
      repo.query!(
        """
        SELECT t.start_at, t.end_at, first_point.id,
          public.ST_Y(first_point.lonlat::public.geometry), public.ST_X(first_point.lonlat::public.geometry),
          last_point.id, public.ST_Y(last_point.lonlat::public.geometry), public.ST_X(last_point.lonlat::public.geometry)
        FROM public.tracks t
        LEFT JOIN LATERAL (SELECT id, lonlat FROM public.points WHERE track_id = t.id ORDER BY timestamp ASC LIMIT 1) first_point ON true
        LEFT JOIN LATERAL (SELECT id, lonlat FROM public.points WHERE track_id = t.id ORDER BY timestamp DESC LIMIT 1) last_point ON true
        WHERE t.user_id = $1 AND t.start_at >= $2 AND t.start_at <= $3 ORDER BY t.start_at
        """,
        params,
        log: false
      ).rows

    values =
      tracks
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.reduce(values, fn [
                                  [_, last, _, _, _, last_id, lat1, lon1],
                                  [first, _, first_id, lat2, lon2, _, _, _]
                                ],
                                values ->
        seconds = epoch(first) - epoch(last)

        if is_nil(first_id) or is_nil(last_id) or seconds <= 0 do
          values
        else
          classify(seconds, distance_km({lat1, lon1}, {lat2, lon2}))
          |> Enum.reduce(values, fn {mode, duration}, values ->
            if duration > 0,
              do: Map.update(values, mode, duration, &(&1 + duration)),
              else: values
          end)
        end
      end)

    total = Enum.sum(Map.values(values))

    if total == 0 do
      %{}
    else
      values
      |> Map.reject(fn {mode, _} -> is_nil(mode) end)
      |> Map.new(fn {mode, duration} ->
        {mode, %{"duration" => duration, "percentage" => round(duration / total * 100)}}
      end)
    end
  end

  def classify(seconds, distance_km) do
    cond do
      seconds <= 86400 and distance_km * 1000 <= 100 ->
        %{"stationary" => seconds, "flying" => 0}

      seconds <= 86400 and distance_km >= 100 and distance_km / (seconds / 3600.0) >= 150 ->
        %{"stationary" => 0, "flying" => seconds}

      true ->
        %{"stationary" => 0, "flying" => 0}
    end
  end

  def distance_km(first, last), do: Dawarich.Geo.safe_distance_m(first, last) / 1000

  defp epoch(time), do: time |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix()
end

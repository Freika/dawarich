defmodule Dawarich.Timeline.Query do
  @moduledoc false
  import Dawarich.Timeline.Sql
  alias Dawarich.{MapWindow, UserSettings, UserTimeZone}

  def normalize(user, params, now, restricted) when is_map(params) do
    with true <-
           Enum.all?(params, fn {_k, v} ->
             is_nil(v) or (is_binary(v) and byte_size(v) <= 1024)
           end),
         true <-
           Enum.all?(Map.take(params, ~w(start_at end_at)), fn {_k, v} ->
             v in [nil, ""] or Dawarich.PointList.valid_params?(%{"start_at" => v})
           end) do
      window = MapWindow.build(params, UserSettings.get(user), now, nil)
      start = unix(window.start)
      stop = unix(window.end)

      cond do
        stop < start ->
          {:error, :invalid_input}

        stop - start > 2_678_400 or Date.diff(window.end_date, window.start_date) > 30 ->
          {:error, :limit}

        true ->
          fingerprint =
            :crypto.hash(
              :sha256,
              :erlang.term_to_binary({user.id, start, stop, window.zone, restricted})
            )
            |> Base.encode16(case: :lower)

          with {:ok, cursor} <- cursor(params["cursor"], fingerprint) do
            {:ok,
             %{
               window: window,
               start: start,
               stop: stop,
               fingerprint: fingerprint,
               cursor: cursor,
               cutoff: if(restricted, do: now)
             }}
          end
      end
    else
      _ -> {:error, :invalid_input}
    end
  rescue
    _ -> {:error, :invalid_input}
  end

  def normalize(_, _, _, _), do: {:error, :invalid_input}

  def keys(user, query, repo) do
    after_key = query.cursor || [nil, nil, nil, nil, nil]

    args =
      [user.id, query.start, query.stop, query.cutoff] ++
        after_key ++ [query.window.start_date, query.window.end_date]

    sql = """
    SELECT day,anchor,started,kind,sort_id FROM (
      SELECT #{day("v.started_at")} AS day, #{epoch("v.started_at")} AS anchor,
             #{epoch("v.started_at")} AS started, 0 AS kind, -v.id AS sort_id
      FROM visits v CROSS JOIN z
      WHERE v.user_id=$1 AND v.deleted_at IS NULL AND v.status<>2
        AND v.started_at BETWEEN #{utc("$2")} AND #{utc("$3")} AND #{windowed("v.started_at", "$4")}
      UNION ALL
      SELECT coalesce(s.day,#{day("t.start_at")}) AS day,
        CASE WHEN s.day IS NOT NULL AND s.day<>#{day("t.start_at")} THEN
          greatest(least(#{epoch("t.end_at")},floor(extract(epoch FROM ((s.day+1)::timestamp AT TIME ZONE z.name)))::bigint-1),floor(extract(epoch FROM (s.day::timestamp AT TIME ZONE z.name)))::bigint)
        ELSE #{epoch("t.start_at")} END AS anchor,
        #{epoch("t.start_at")} AS started, 1 AS kind, t.id AS sort_id
      FROM tracks t CROSS JOIN z #{shares("t", "$10::date", "$11::date")}
      WHERE t.user_id=$1 AND t.start_at<=#{utc("$3")} AND t.end_at>=#{utc("$2")}
        AND NOT(t.dominant_mode=1 AND t.distance<100) AND #{windowed("t.start_at", "$4")}
        AND coalesce(s.day,#{day("t.start_at")}) BETWEEN $10::date AND $11::date
    ) entries
    WHERE ($5::date IS NULL OR (day,anchor,started,kind,sort_id)>($5::date,$6::bigint,$7::bigint,$8::int,$9::bigint))
    ORDER BY day,anchor,started,kind,sort_id LIMIT 101
    """

    UserTimeZone.query!(sql, args, UserSettings.get(user), repo).rows
  end

  def next(key, fingerprint),
    do:
      Jason.encode!([
        fingerprint
        | Enum.map(key, fn value ->
            if match?(%Date{}, value), do: Date.to_iso8601(value), else: value
          end)
      ])
      |> Base.url_encode64(padding: false)

  defp cursor(value, _) when value in [nil, ""], do: {:ok, nil}

  defp cursor(value, fingerprint) when is_binary(value) and byte_size(value) <= 512 do
    with {:ok, json} <- Base.url_decode64(value, padding: false),
         {:ok, [^fingerprint, day, anchor, start, kind, id]} <- Jason.decode(json),
         {:ok, date} <- Date.from_iso8601(day),
         true <-
           kind in [0, 1] and
             Enum.all?(
               [anchor, start, id],
               &(is_integer(&1) and abs(&1) <= 9_223_372_036_854_775_807)
             ) do
      {:ok, [date, anchor, start, kind, id]}
    else
      _ -> {:error, :invalid_input}
    end
  end

  defp cursor(_, _), do: {:error, :invalid_input}

  defp unix(value) do
    {:ok, at, _} = DateTime.from_iso8601(value)
    DateTime.to_unix(at)
  end
end

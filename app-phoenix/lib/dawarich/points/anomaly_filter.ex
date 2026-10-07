defmodule Dawarich.Points.AnomalyFilter do
  @moduledoc false
  alias Dawarich.Points.AnomalyFilter.{Effects, Query, Speed}

  @departure "COALESCE(motion_data->>'departure_date', raw_data->'properties'->>'departure_date')"
  @false_values [false, 0, "0", "f", "F", "false", "FALSE", "off", "OFF", ""]

  def call(repo, user_id, start_ts, end_ts, opts \\ []) do
    if enabled?(repo, user_id) do
      context = %{
        repo: repo,
        user_id: user_id,
        first: start_ts,
        last: end_ts,
        zone:
          Dawarich.TimeZoneName.to_iana(
            Keyword.get(opts, :zone, System.get_env("TIME_ZONE", "Europe/Berlin"))
          ),
        fence: Keyword.get(opts, :fence, fn fun -> fun.() end)
      }

      flagged =
        flag(
          context,
          "ST_DWithin(lonlat::geography, ST_SetSRID(ST_MakePoint(0,0),4326)::geography,5000)"
        ) ++
          flag(context, "accuracy > 10000") ++
          flag(
            context,
            "motion_data->>'action'='visit' AND #{@departure} ~ '^\\d{4}-' AND #{@departure} < '3000-'",
            ", motion_data = motion_data || jsonb_build_object('departure_date', #{@departure})"
          ) ++
          sentinel(context) ++ speed(context)

      Effects.call(context, flagged, opts)
      length(flagged)
    else
      0
    end
  end

  defp enabled?(repo, user_id) do
    case repo.query!("SELECT settings FROM users WHERE id=$1", [user_id], log: false).rows do
      [[settings]] ->
        Dawarich.UserSettings.safe(settings)["gps_filtering_enabled"] not in @false_values

      [] ->
        raise ArgumentError, "anomaly filter user does not exist"
    end
  end

  defp flag(context, condition, extra \\ "") do
    flagged =
      context.repo.query!(
        "SELECT id,track_id,timestamp FROM points WHERE user_id=$1 AND timestamp BETWEEN $2::bigint AND $3::bigint AND anomaly IS NOT TRUE AND #{condition}",
        [context.user_id, context.first, context.last],
        log: false
      ).rows

    update(context, flagged, extra)
  end

  defp sentinel(context) do
    flag(%{context | first: context.first - 21_600}, """
    vertical_accuracy < 0 AND velocity LIKE '-%' AND accuracy > 500
    AND EXISTS (SELECT 1 FROM points precise
      WHERE precise.user_id=points.user_id
        AND precise.tracker_id IS NOT DISTINCT FROM points.tracker_id
        AND precise.timestamp BETWEEN points.timestamp-21600 AND points.timestamp+21600
        AND precise.accuracy<=100 AND precise.anomaly IS NOT TRUE AND precise.id<>points.id)
    """)
  end

  defp speed(context), do: speed_chunks(context, context.first, [])

  defp speed_chunks(context, first, rows) when first > context.last,
    do: Enum.reverse(rows) |> Enum.flat_map(& &1)

  defp speed_chunks(context, first, rows) do
    last = min(Query.month_end(context, first), context.last)
    {points, judged} = Query.context(context, first, last)
    ids = Speed.anomalies(points, judged, Query.speeds(context, points), first, last)

    flagged =
      if ids == [],
        do: [],
        else:
          context.repo.query!(
            "SELECT id,track_id,timestamp FROM points WHERE id=ANY($1::bigint[])",
            [ids],
            log: false
          ).rows

    flagged = update(context, flagged, "")
    speed_chunks(context, last + 1, [flagged | rows])
  end

  defp update(_context, [], _extra), do: []

  defp update(context, rows, extra) do
    context.fence.(fn ->
      context.repo.query!(
        "UPDATE points SET anomaly=TRUE,track_id=NULL,updated_at=NOW()#{extra} WHERE id=ANY($1::bigint[])",
        [Enum.map(rows, &hd/1)],
        log: false
      )
    end)

    rows
  end
end

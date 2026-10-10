defmodule Dawarich.TripPage do
  @moduledoc false

  alias Dawarich.{
    CountryNames,
    Repo,
    TripDays,
    TripSettings,
    TripStream,
    TripStudio,
    UserTimeZone
  }

  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  @gate """
  SELECT z.name, s.sl, s.el, s.seconds, s.near_transition,
         t.started_at < '1901-12-13 20:45:52'
           OR t.ended_at >= '2038-01-19 03:14:08'
           OR NOT CASE WHEN t.visited_countries IS NULL OR t.visited_countries IN ('null'::jsonb, '{}'::jsonb) THEN true
                       WHEN jsonb_typeof(t.visited_countries) <> 'array' THEN false
                       ELSE NOT EXISTS (SELECT 1 FROM jsonb_array_elements(t.visited_countries) e
                                        WHERE jsonb_typeof(e) <> 'string') END,
         (SELECT r.body FROM action_text_rich_texts r
          WHERE r.record_type = 'Trip' AND r.record_id = t.id AND r.name = 'description')
  FROM trips t CROSS JOIN z
  CROSS JOIN LATERAL (#{TripDays.span_sql("t.started_at", "t.ended_at", "z.name")}) s
  WHERE t.id = $1 AND t.user_id = $2
  """

  def gate(user, trip_id) do
    with {:ok, settings} <- TripSettings.read(Dawarich.UserSettings.get(user)),
         true <- Dawarich.Trips.PlanRead.supported?(Repo, user.id, trip_id),
         [[zone, started_local, ended_local, seconds, near_transition, false, body]] <-
           UserTimeZone.query!(@gate, [trip_id, user.id], Dawarich.UserSettings.get(user)).rows,
         {:ok, description} <- Dawarich.Trips.RichContent.read(body),
         true <- TripSettings.zone?(Dawarich.UserSettings.get(user), zone),
         span = TripDays.span(started_local, ended_local, seconds, near_transition),
         {_parts, borrowed} =
           TripDays.duration_parts(span.started_local, span.ended_local, span.previous_month_days),
         false <- borrowed and span.near_transition do
      {:ok, %{settings: settings, zone: zone, span: span, description: description}}
    else
      _ -> :rails
    end
  end

  @trip """
  SELECT t.name, t.distance, t.visited_countries, t.started_at, t.ended_at,
         ((t.started_at AT TIME ZONE 'UTC') AT TIME ZONE $2)::date,
         ((t.ended_at AT TIME ZONE 'UTC') AT TIME ZONE $2)::date,
         floor(extract(epoch FROM t.started_at AT TIME ZONE 'UTC'))::bigint,
         floor(extract(epoch FROM t.ended_at AT TIME ZONE 'UTC'))::bigint,
         coalesce(t.last_recalculated_at > $3::timestamp - interval '60 seconds', false),
         EXISTS (SELECT 1 FROM shared_links s
                 WHERE s.resource_type = 0 AND s.resource_id = t.id AND s.revoked_at IS NULL
                   AND (s.expires_at IS NULL OR s.expires_at > $3::timestamp)),
         CASE WHEN ST_IsEmpty(t.path) THEN ARRAY[]::float8[]
              ELSE (SELECT array_agg(ARRAY[ST_X(p.geom), ST_Y(p.geom)] ORDER BY p.path) FROM ST_DumpPoints(t.path) p) END,
         t.path IS NOT NULL AND NOT ST_IsEmpty(t.path), t.source_identifier
  FROM trips t WHERE t.id = $1
  """

  @notes """
  SELECT n.id, n.noted_at::date, n.body, n.source_digest FROM notes n
  WHERE n.attachable_type = 'Trip' AND n.attachable_id = $1 AND n.noted_at IS NOT NULL
  """

  def load(user, trip_id, now) do
    with {:ok, gated} <- gate(user, trip_id),
         [row] <- Repo.query!(@trip, [trip_id, gated.zone, DateTime.to_naive(now)]).rows do
      {:ok, page(user, trip_id, row, gated, now)}
    else
      _ -> :rails
    end
  end

  defp page(user, id, row, %{settings: settings, zone: zone, span: span} = gated, now) do
    [
      name,
      distance,
      countries,
      started,
      ended,
      first_day,
      last_day,
      from,
      to,
      recalculating,
      shared,
      path,
      has_path,
      source_identifier
    ] = row

    day_data = TripDays.day_data(user.id, from, to, settings.minutes * 60, zone)
    notes = day_notes(id)
    photos = Dawarich.Trips.Photos.load(user, started, ended, zone)
    {:ok, plan} = Dawarich.Trips.PlanRead.load(Repo, user.id, id)
    plan = DawarichWeb.TripPlanItems.prepare(plan, Dawarich.UserSettings.get(user))

    future =
      Ruby.present?(source_identifier) and
        NaiveDateTime.compare(started, DateTime.to_naive(now)) == :gt

    geojson = Dawarich.Trips.PlanGeojson.build(plan)
    plan_map = not has_path and geojson != nil and (future or map_size(day_data.stats) == 0)

    state =
      cond do
        has_path -> :path
        plan_map -> :plan
        future -> :future
        map_size(day_data.stats) == 0 -> :empty
        true -> :calculating
      end

    {duration, _borrowed} =
      TripDays.duration_parts(span.started_local, span.ended_local, span.previous_month_days)

    %{
      id: id,
      name: name,
      distance: distance,
      countries: if(is_list(countries), do: Enum.sort(countries), else: []),
      flags: CountryNames.table(),
      settings: settings,
      api_key: user.api_key,
      iana: zone,
      started_at:
        UserTimeZone.zoned(started, NaiveDateTime.diff(span.started_local, started), zone),
      ended_at: UserTimeZone.zoned(ended, NaiveDateTime.diff(span.ended_local, ended), zone),
      duration: duration,
      recalculating: recalculating,
      shared: shared,
      path_json: if(path, do: IO.iodata_to_binary(Ruby.json(path)), else: ""),
      has_path: has_path,
      map_state: state,
      windows_json: day_data.windows_json,
      days: days(first_day, last_day, day_data.stats, notes, photos.days),
      photos: photos,
      day_notes: notes,
      plan: plan,
      now: now,
      plan_on_map: geojson != nil and (has_path or plan_map),
      plan_json: Dawarich.Trips.PlanGeojson.encode(geojson),
      plan_toggle: has_path and geojson != nil,
      future_start: NaiveDateTime.compare(started, DateTime.to_naive(now)) == :gt,
      description: gated.description,
      trip_stream: TripStream.stream_name(id),
      studio: TripStudio.load(user.id, zone)
    }
  end

  defp days(first, last, stats, notes, photos),
    do:
      for(
        date <- Date.range(first, last, 1),
        do: %{date: date, stats: stats[date], note: notes[date], photos: photos[date] || []}
      )

  def day_notes(trip_id),
    do:
      Repo.query!(@notes, [trip_id]).rows
      |> Map.new(fn [id, date, body, digest] ->
        {date, %{id: id, date: date, body: body, source_digest: digest}}
      end)
end

defmodule Dawarich.Trips.DetailProjection do
  @moduledoc false

  alias Dawarich.{Repo, TripDays, UserTimeZone}
  alias Dawarich.Trips.{PlanRead, RichContent}
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  @header """
  SELECT t.name, t.distance,
         CASE WHEN jsonb_typeof(t.visited_countries) = 'array'
              THEN ARRAY(SELECT e #>> '{}' FROM jsonb_array_elements(t.visited_countries) e
                         WHERE jsonb_typeof(e) = 'string' ORDER BY 1)
              ELSE ARRAY[]::text[] END,
         t.started_at, t.ended_at, z.name, s.sl, s.el, s.seconds, s.near_transition,
         coalesce(t.last_recalculated_at > $3::timestamp - interval '60 seconds', false),
         EXISTS (SELECT 1 FROM shared_links l
                 WHERE l.resource_type = 0 AND l.resource_id = t.id AND l.revoked_at IS NULL
                   AND (l.expires_at IS NULL OR l.expires_at > $3::timestamp)),
         t.path IS NOT NULL AND NOT ST_IsEmpty(t.path), t.source_identifier,
         (SELECT r.body FROM action_text_rich_texts r
          WHERE r.record_type = 'Trip' AND r.record_id = t.id AND r.name = 'description'),
         #{PlanRead.supported_sql("t.id", "$2")}
  FROM trips t CROSS JOIN z
  CROSS JOIN LATERAL (#{TripDays.span_sql("t.started_at", "t.ended_at", "z.name")}) s
  WHERE t.id = $1 AND t.user_id = $2
  """

  @notes """
  SELECT n.id, n.noted_at::date, n.body, n.source_digest FROM notes n
  WHERE n.attachable_type = 'Trip' AND n.attachable_id = $1 AND n.noted_at IS NOT NULL
  """

  def load(user, id, settings, now) do
    case UserTimeZone.query!(@header, [id, user.id, DateTime.to_naive(now)], user_settings(user)).rows do
      [row] -> {:ok, project(user, id, row, settings, now)}
      [] -> {:error, :not_found}
    end
  end

  defp project(user, id, row, settings, now) do
    [
      name,
      distance,
      countries,
      started,
      ended,
      zone,
      sl,
      el,
      seconds,
      near,
      recalculating,
      shared,
      has_path,
      source,
      body,
      plan_supported
    ] = row

    span = TripDays.span(sl, el, seconds, near)
    {duration, _borrowed} = TripDays.duration_parts(sl, el, span.previous_month_days)
    future = NaiveDateTime.compare(started, DateTime.to_naive(now)) == :gt

    %{
      id: id,
      name: name,
      distance: distance,
      countries: countries,
      zone: zone,
      started_at: UserTimeZone.zoned(started, NaiveDateTime.diff(sl, started), zone),
      ended_at: UserTimeZone.zoned(ended, NaiveDateTime.diff(el, ended), zone),
      first_day: NaiveDateTime.to_date(sl),
      last_day: NaiveDateTime.to_date(el),
      duration: duration,
      recalculating: recalculating,
      shared: shared,
      has_path: has_path,
      future_start: future,
      planned_future: Ruby.present?(source) and future,
      description: description(body),
      plan: plan(user, id, plan_supported),
      notes: notes(id),
      settings: Map.take(settings, [:unit, :factor, :photos])
    }
  end

  defp description(body) do
    case RichContent.read(body) do
      {:ok, html} -> html
      _ -> :unavailable
    end
  end

  defp plan(_user, _id, false), do: nil

  defp plan(user, id, true) do
    case PlanRead.load(Repo, user.id, id) do
      {:ok, plan} -> plan
      _ -> nil
    end
  end

  defp notes(id),
    do:
      Repo.query!(@notes, [id]).rows
      |> Map.new(fn [note_id, date, body, digest] ->
        {date, %{id: note_id, date: date, body: body, source_digest: digest}}
      end)

  defp user_settings(user), do: Dawarich.UserSettings.get(user)
end

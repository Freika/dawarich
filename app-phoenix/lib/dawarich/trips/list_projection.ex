defmodule Dawarich.Trips.ListProjection do
  @moduledoc false

  alias Dawarich.UserTimeZone
  alias Dawarich.Trips.PlanRead

  @per_page 6
  @day_us 86_400_000_000

  @located "s.latitude IS NOT NULL AND s.longitude IS NOT NULL"

  def per_page, do: @per_page

  def cards(user, page) do
    settings = Dawarich.UserSettings.get(user)

    %{rows: rows} =
      UserTimeZone.query!(sql(), [user.id, (page - 1) * @per_page], settings)

    %{entries: Enum.map(rows, &card/1), total_pages: total_pages(rows)}
  end

  defp sql do
    """
    SELECT t.id, t.name, t.distance,
           CASE WHEN jsonb_typeof(t.visited_countries) = 'array'
                THEN (SELECT count(*) FROM jsonb_array_elements(t.visited_countries) e
                      WHERE jsonb_typeof(e) = 'string')
                ELSE 0 END,
           t.path IS NOT NULL AND NOT ST_IsEmpty(t.path),
           #{PlanRead.supported_sql("t.id", "$1")} AND (
             EXISTS (SELECT 1 FROM planned_stops s JOIN planned_days d ON d.id = s.planned_day_id
                     WHERE d.trip_id = t.id AND #{@located})
             OR EXISTS (SELECT 1 FROM planned_accommodations s WHERE s.trip_id = t.id AND #{@located})
             OR EXISTS (SELECT 1 FROM planned_unplanned_places s WHERE s.trip_id = t.id AND #{@located})),
           ((t.started_at AT TIME ZONE 'UTC') AT TIME ZONE z.name)::date,
           ((t.ended_at AT TIME ZONE 'UTC') AT TIME ZONE z.name)::date,
           (extract(epoch FROM t.ended_at - t.started_at) * 1000000)::bigint,
           (SELECT count(*) FROM trips c WHERE c.user_id = $1)
    FROM (SELECT * FROM trips WHERE user_id = $1 ORDER BY started_at DESC
          LIMIT #{@per_page} OFFSET $2) t CROSS JOIN z
    ORDER BY t.started_at DESC
    """
  end

  defp card([id, name, distance, countries, path, plan, started_on, ended_on, span_us, _total]) do
    %{
      id: id,
      name: name,
      distance: distance,
      countries: countries,
      started_on: started_on,
      ended_on: ended_on,
      day_count: day_count(span_us),
      preview: preview(path, plan, distance)
    }
  end

  defp day_count(nil), do: 1
  defp day_count(span_us), do: max(-Integer.floor_div(-span_us, @day_us), 1)

  defp preview(true, _plan, _distance), do: :path
  defp preview(_path, true, _distance), do: :plan
  defp preview(_path, _plan, nil), do: :calculating
  defp preview(_path, _plan, _distance), do: :no_points

  defp total_pages([]), do: 0
  defp total_pages([row | _]), do: div(List.last(row) + @per_page - 1, @per_page)
end

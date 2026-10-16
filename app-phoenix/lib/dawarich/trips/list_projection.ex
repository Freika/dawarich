defmodule Dawarich.Trips.ListProjection do
  @moduledoc false

  alias Dawarich.UserTimeZone
  alias Dawarich.Trips.{IndexQuery, PlanRead}

  @per_page 6
  @day_us 86_400_000_000

  @located "s.latitude IS NOT NULL AND s.longitude IS NOT NULL"

  def per_page, do: @per_page

  def cards(user, query) do
    settings = Dawarich.UserSettings.get(user)

    %{rows: rows} =
      UserTimeZone.query!(
        sql(query),
        IndexQuery.params(user, query, (query.page - 1) * @per_page),
        settings
      )

    %{
      entries: rows |> Enum.reject(&is_nil(hd(&1))) |> Enum.map(&card/1),
      total_pages: total_pages(rows)
    }
  end

  defp sql(query) do
    IndexQuery.matched() <>
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
             counts.total
      FROM (SELECT count(*) AS total FROM matched) counts CROSS JOIN z
      LEFT JOIN LATERAL (SELECT * FROM matched t ORDER BY #{IndexQuery.order(query)}
            LIMIT #{@per_page} OFFSET $2) t ON true
      ORDER BY #{IndexQuery.order(query)}
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

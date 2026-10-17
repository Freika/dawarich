defmodule Dawarich.Trips.IndexQuery do
  @moduledoc false
  alias Dawarich.{Accounts.Scope, UserSettings, UserTimeZone}

  @sorts %{
    "newest" => "t.started_at DESC, t.id DESC",
    "oldest" => "t.started_at ASC, t.id ASC",
    "name" => "lower(t.name) ASC, t.id ASC",
    "distance" => "t.distance DESC NULLS LAST, t.id DESC"
  }

  def normalize(params) do
    year = integer(params["year"], 1900..2200)

    %{
      q: params["q"] |> text() |> String.codepoints() |> Enum.take(100) |> Enum.join(),
      sort: if(Map.has_key?(@sorts, params["sort"]), do: params["sort"], else: "newest"),
      year: year,
      month: if(year, do: integer(params["month"], 1..12)),
      country: text(params["country"])
    }
  end

  def active?(query), do: query.q != "" or query.year != nil or query.country != ""
  def order(query), do: Map.fetch!(@sorts, query.sort)

  def params(user, query, offset) do
    pattern =
      query.q
      |> String.replace("\\", "\\\\")
      |> String.replace("%", "\\%")
      |> String.replace("_", "\\_")

    [
      user.id,
      offset,
      if(query.q != "", do: "%" <> pattern <> "%"),
      query.year,
      query.month,
      if(query.country != "", do: query.country)
    ]
  end

  def options(%Scope{user: user}) do
    %{rows: [[years, countries]]} =
      UserTimeZone.query!(
        """
        SELECT ARRAY(SELECT DISTINCT generate_series(
          extract(year FROM ((t.started_at AT TIME ZONE 'UTC') AT TIME ZONE z.name))::int,
          extract(year FROM ((t.ended_at AT TIME ZONE 'UTC') AT TIME ZONE z.name))::int)
          AS year FROM trips t CROSS JOIN z WHERE t.user_id=$1 ORDER BY year DESC),
          ARRAY(SELECT DISTINCT e.country FROM trips t CROSS JOIN LATERAL
            jsonb_array_elements_text(CASE WHEN jsonb_typeof(t.visited_countries)='array'
              THEN t.visited_countries ELSE '[]'::jsonb END) e(country)
            WHERE t.user_id=$1 ORDER BY e.country)
        """,
        [user.id],
        UserSettings.get(user)
      )

    %{years: years, countries: Enum.sort_by(countries, &String.downcase/1)}
  end

  def matched do
    """
    , matched AS MATERIALIZED (
      SELECT t.* FROM trips t CROSS JOIN z
      WHERE t.user_id=$1
        AND ($3::text IS NULL OR (#{search()}))
        AND ($4::int IS NULL OR (
          t.started_at < ((make_date($4, coalesce($5::int,1), 1)::timestamp +
            CASE WHEN $5::int IS NULL THEN interval '1 year' ELSE interval '1 month' END)
            AT TIME ZONE z.name) AT TIME ZONE 'UTC'
          AND t.ended_at >= (make_date($4, coalesce($5::int,1), 1)::timestamp
            AT TIME ZONE z.name) AT TIME ZONE 'UTC'))
        AND ($6::text IS NULL OR (jsonb_typeof(t.visited_countries)='array'
          AND t.visited_countries @> jsonb_build_array($6::text)))
    )
    """
  end

  defp search do
    """
    t.name ILIKE $3
    OR EXISTS (SELECT 1 FROM jsonb_array_elements_text(
      CASE WHEN jsonb_typeof(t.visited_countries)='array' THEN t.visited_countries
        ELSE '[]'::jsonb END) e(country) WHERE e.country ILIKE $3)
    OR EXISTS (SELECT 1 FROM action_text_rich_texts r WHERE r.record_type='Trip'
      AND r.record_id=t.id AND r.name='description' AND
      replace(replace(replace(replace(replace(replace(
        regexp_replace(r.body, '<[^>]*>', ' ', 'g'), '&nbsp;', ' '), '&lt;', '<'),
        '&gt;', '>'), '&quot;', '"'), '&#39;', ''''), '&amp;', '&') ILIKE $3)
    OR EXISTS (SELECT 1 FROM notes n WHERE n.attachable_type='Trip' AND n.attachable_id=t.id
      AND (n.title ILIKE $3 OR n.body ILIKE $3))
    OR EXISTS (SELECT 1 FROM planned_days d WHERE d.trip_id=t.id AND
      (d.title ILIKE $3 OR d.notes ILIKE $3 OR EXISTS (
        SELECT 1 FROM planned_stops s WHERE s.planned_day_id=d.id AND
          (s.name ILIKE $3 OR s.address ILIKE $3 OR s.notes ILIKE $3))))
    OR EXISTS (SELECT 1 FROM planned_unplanned_places p WHERE p.trip_id=t.id
      AND (p.name ILIKE $3 OR p.address ILIKE $3 OR p.notes ILIKE $3))
    OR EXISTS (SELECT 1 FROM planned_accommodations p WHERE p.trip_id=t.id
      AND (p.name ILIKE $3 OR p.address ILIKE $3 OR p.notes ILIKE $3))
    OR EXISTS (SELECT 1 FROM planned_reservations p WHERE p.trip_id=t.id
      AND (p.title ILIKE $3 OR p.location ILIKE $3 OR p.notes ILIKE $3))
    """
  end

  defp integer(value, range) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {n, ""} -> if n in range, do: n
      _ -> nil
    end
  end

  defp integer(value, range) when is_integer(value), do: if(value in range, do: value)
  defp integer(_, _), do: nil
  defp text(value) when is_binary(value), do: value |> String.replace(<<0>>, "") |> String.trim()
  defp text(_), do: ""
end

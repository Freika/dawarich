defmodule Dawarich.Stats.IndexReads do
  @moduledoc false
  alias Dawarich.{Repo, Stats, RubyInteger}
  alias Dawarich.Analytics.Period

  @places """
  WITH RECURSIVE top(value) AS (
    SELECT toponyms FROM stats WHERE user_id=$1
    UNION ALL
    SELECT entry.value FROM top
    CROSS JOIN LATERAL jsonb_array_elements(CASE WHEN jsonb_typeof(top.value)='array' THEN top.value ELSE '[]'::jsonb END) entry
  ), places AS (
    SELECT top.value->>'country' AS country, c.city->>'city' AS city
    FROM top CROSS JOIN LATERAL jsonb_array_elements(CASE WHEN jsonb_typeof(top.value->'cities')='array' THEN top.value->'cities' ELSE '[]'::jsonb END) AS c(city)
    WHERE jsonb_typeof(top.value)='object'
      AND (top.value->'country' IS NULL OR jsonb_typeof(top.value->'country') IN ('null','string'))
      AND jsonb_typeof(c.city)='object' AND jsonb_typeof(c.city->'city')='string'
      AND c.city->>'city' ~ '[^[:space:]]'
  ), countries AS (SELECT DISTINCT country AS name FROM places WHERE country ~ '[^[:space:]]'),
  cities AS (SELECT DISTINCT city AS name FROM places)
  SELECT (SELECT count(*) FROM countries), (SELECT count(*) FROM cities),
    ARRAY(SELECT name FROM countries ORDER BY name COLLATE "C" LIMIT 50 OFFSET $2),
    ARRAY(SELECT name FROM cities ORDER BY name COLLATE "C" LIMIT 50 OFFSET $2)
  """

  def load(id, period, params) do
    [[total_years, distance]] =
      Repo.query!(
        "SELECT count(DISTINCT year),COALESCE(sum(distance),0) FROM stats WHERE user_id=$1",
        [id],
        log: false
      ).rows

    visible =
      Repo.query!(
        "SELECT DISTINCT year FROM stats WHERE user_id=$1 ORDER BY year DESC LIMIT 50 OFFSET $2",
        [id, (period.page - 1) * 50],
        log: false
      ).rows
      |> List.flatten()

    rows =
      Repo.query!(
        "SELECT year,month,distance,toponyms,(updated_at AT TIME ZONE 'UTC' AT TIME ZONE $3)::date FROM stats WHERE user_id=$1 AND year=ANY($2::int[]) ORDER BY year DESC,updated_at DESC",
        [id, visible, period.zone],
        log: false
      ).rows

    admitted =
      for [year, month, distance, toponyms, updated] <- rows,
          Stats.in_window?(%{year: year, month: month}, period.cutoff),
          do: %{
            year: year,
            month: month,
            distance: distance,
            toponyms: Period.narrow(toponyms),
            updated_on: updated
          }

    years =
      admitted
      |> Enum.chunk_by(& &1.year)
      |> Enum.map(fn [first | _] = stats ->
        %{
          year: first.year,
          updated_on: first.updated_on,
          stats: stats,
          distances:
            for(
              month <- 1..12,
              do: Enum.find_value(stats, 0, &(&1.month == month and &1.distance))
            )
        }
      end)

    places_page = max(1, min(RubyInteger.to_i(params["places_page"] || "1"), 1_000_000_000_000))

    [[countries_count, cities_count, countries, cities]] =
      Repo.query!(@places, [id, (places_page - 1) * 50], log: false).rows

    %{
      years: years,
      locked_years: if(period.restricted, do: visible -- Enum.map(years, & &1.year), else: []),
      total_distance:
        if(is_struct(distance, Decimal), do: Decimal.to_integer(distance), else: distance),
      total_pages: ceil(total_years / 50),
      page: period.page,
      more: period.page < ceil(total_years / 50),
      countries_visited: countries,
      cities_visited: cities,
      total_countries: countries_count,
      total_cities: cities_count,
      places_page: places_page,
      places_more: max(countries_count, cities_count) > places_page * 50
    }
  end
end

defmodule Dawarich.TripList do
  @moduledoc false

  alias Dawarich.{TripSettings, UserTimeZone}

  @per_page 6
  @max_page 1_000_000_000_000

  @trips "(SELECT * FROM trips WHERE user_id = $1 ORDER BY started_at DESC LIMIT #{@per_page} OFFSET $2) t"

  @rails """
  (ST_IsEmpty(t.path) IS TRUE
   OR (t.path IS NULL AND (EXISTS (SELECT 1 FROM planned_days x WHERE x.trip_id = t.id)
                           OR EXISTS (SELECT 1 FROM planned_accommodations x WHERE x.trip_id = t.id)
                           OR EXISTS (SELECT 1 FROM planned_unplanned_places x WHERE x.trip_id = t.id)))
   OR NOT CASE WHEN jsonb_typeof(t.visited_countries) = 'array'
               THEN NOT EXISTS (SELECT 1 FROM jsonb_array_elements(t.visited_countries) e
                                WHERE jsonb_typeof(e) <> 'string')
               ELSE t.visited_countries = '{}'::jsonb END)
  """

  @gate "SELECT coalesce((SELECT bool_or(#{@rails}) FROM #{@trips}), false), z.name FROM z"

  def gate(_user, page) when page > @max_page, do: :rails

  def gate(user, page) do
    with {:ok, _settings} <- TripSettings.read(user.settings),
         [[false, zone]] <-
           UserTimeZone.query!(@gate, [user.id, offset(page)], user.settings).rows,
         true <- TripSettings.zone?(user.settings, zone) do
      :phoenix
    else
      _ -> :rails
    end
  end

  def offset(page), do: (page - 1) * @per_page
end

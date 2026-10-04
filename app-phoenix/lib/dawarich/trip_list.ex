defmodule Dawarich.TripList do
  @moduledoc false

  alias Dawarich.{TripSettings, UserTimeZone}
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  @per_page 6
  @max_page 1_000_000_000_000
  @day_us 86_400_000_000

  @trips "(SELECT * FROM trips WHERE user_id = $1 ORDER BY started_at DESC LIMIT #{@per_page} OFFSET $2) t"

  @rails """
  (NOT CASE WHEN jsonb_typeof(t.visited_countries) = 'array'
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
         true <- TripSettings.zone?(user.settings, zone),
         true <- supported_plans?(user.id, page) do
      :phoenix
    else
      _ -> :rails
    end
  end

  def offset(page), do: (page - 1) * @per_page

  defp supported_plans?(user_id, page) do
    Dawarich.Repo.query!("SELECT t.id FROM #{@trips}", [user_id, offset(page)], log: false).rows
    |> Enum.all?(fn [id] -> Dawarich.Trips.PlanRead.supported?(Dawarich.Repo, user_id, id) end)
  end

  @page """
  SELECT t.id, t.name, t.distance,
         CASE WHEN jsonb_typeof(t.visited_countries) = 'array' THEN jsonb_array_length(t.visited_countries) ELSE 0 END,
         (SELECT array_agg(ARRAY[ST_X(p.geom), ST_Y(p.geom)] ORDER BY p.path) FROM ST_DumpPoints(t.path) p),
         ((t.started_at AT TIME ZONE 'UTC') AT TIME ZONE z.name)::date,
         ((t.ended_at AT TIME ZONE 'UTC') AT TIME ZONE z.name)::date,
         (extract(epoch FROM t.ended_at - t.started_at) * 1000000)::bigint,
         #{@rails},
         (SELECT count(*) FROM trips c WHERE c.user_id = $1),
         z.name
  FROM #{@trips} CROSS JOIN z
  ORDER BY t.started_at DESC
  """

  def load(_user, page) when page > @max_page, do: :rails

  def load(user, page) do
    with {:ok, settings} <- TripSettings.read(user.settings),
         %{rows: rows} <- UserTimeZone.query!(@page, [user.id, offset(page)], user.settings),
         false <- Enum.any?(rows, &Enum.at(&1, 8)),
         true <- zone_ok?(user.settings, rows),
         true <- supported_plans?(user.id, page) do
      {:ok,
       %{
         entries: Enum.map(rows, &entry(&1, user.id)),
         total_pages: total_pages(rows),
         settings: settings
       }}
    else
      _ -> :rails
    end
  end

  defp entry(
         [
           id,
           name,
           distance,
           countries,
           path,
           started_on,
           ended_on,
           span_us,
           _rails,
           _total,
           _zone
         ],
         user_id
       ) do
    {:ok, plan} = Dawarich.Trips.PlanRead.load(Dawarich.Repo, user_id, id)
    geojson = Dawarich.Trips.PlanGeojson.build(plan)

    %{
      id: id,
      name: name,
      distance: distance,
      countries: countries,
      path_json: path && IO.iodata_to_binary(Ruby.json(path)),
      plan_json: Dawarich.Trips.PlanGeojson.encode(geojson),
      started_on: started_on,
      ended_on: ended_on,
      day_count: max(-Integer.floor_div(-span_us, @day_us), 1)
    }
  end

  defp zone_ok?(_settings, []), do: true
  defp zone_ok?(settings, [row | _]), do: TripSettings.zone?(settings, List.last(row))

  defp total_pages([]), do: 0
  defp total_pages([row | _]), do: div(Enum.at(row, 9) + @per_page - 1, @per_page)
end

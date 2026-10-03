defmodule Dawarich.PlaceList do
  @moduledoc false

  alias Dawarich.{MapPage, RubyInteger, TripSettings, UserTimeZone}

  @per_page 20
  @max_page 1_000_000_000_000_000

  @sql """
  SELECT p.id, p.name, ST_Y(p.lonlat::geometry), ST_X(p.lonlat::geometry), p.latitude, p.longitude,
         p.created_at,
         extract(epoch FROM ((p.created_at AT TIME ZONE 'UTC') AT TIME ZONE z.name) - p.created_at)::int,
         z.name, count(*) OVER ()
  FROM public.places p
  CROSS JOIN z
  WHERE p.user_id = $1
  ORDER BY p.id
  LIMIT #{@per_page} OFFSET $2
  """

  def load(user, page) do
    number = max(RubyInteger.to_i(page), 1)

    if number <= @max_page and settings?(user.settings),
      do: page(user, number, user.settings || %{}),
      else: :rails
  end

  def settings?(nil), do: true
  def settings?(%{"timezone" => zone}) when not is_nil(zone) and not is_binary(zone), do: false
  def settings?(settings), do: is_map(settings)

  defp page(user, number, settings) do
    case UserTimeZone.query!(@sql, [user.id, (number - 1) * @per_page], settings).rows do
      [] ->
        {:ok, %{entries: [], total_pages: 0}}

      [[_, _, _, _, _, _, _, _, zone, total] | _] = rows ->
        if TripSettings.zone?(settings, zone),
          do:
            {:ok,
             %{
               entries: Enum.map(rows, &entry/1),
               total_pages: div(total + @per_page - 1, @per_page)
             }},
          else: :rails
    end
  end

  defp entry([id, name, lat, lon, latitude, longitude, created_at, offset, zone, _total]),
    do: %{
      id: id,
      name: name,
      lat: MapPage.coordinate(lat, latitude),
      lon: MapPage.coordinate(lon, longitude),
      created: UserTimeZone.zoned(created_at, offset, zone)
    }
end

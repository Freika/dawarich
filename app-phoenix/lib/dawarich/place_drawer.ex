defmodule Dawarich.PlaceDrawer do
  @moduledoc false

  alias Dawarich.{PlaceList, TripSettings, UserTimeZone}

  @sources ~w(manual photon gpx_waypoint)
  @active "v.place_id = p.id AND v.deleted_at IS NULL AND v.status <> 2"

  @sql """
  SELECT p.id, p.name, p.note, p.city, p.country, p.source, p.name_locked_at IS NOT NULL,
         (SELECT count(*) FROM public.visits v WHERE #{@active}),
         (SELECT coalesce(sum(v.duration), 0) FROM public.visits v WHERE #{@active}),
         (SELECT coalesce(json_agg(json_build_array(t.name, t.icon, t.color) ORDER BY g.created_at, g.id), '[]')
            FROM public.taggings g JOIN public.tags t ON t.id = g.tag_id
            WHERE g.taggable_type = 'Place' AND g.taggable_id = p.id),
         (SELECT coalesce(json_agg(json_build_array(r.name, r.duration, r.started, r.ended)
                                   ORDER BY r.started_at DESC, r.id DESC), '[]')
            FROM (SELECT v.id, v.name, v.duration, v.started_at,
                         (v.started_at AT TIME ZONE 'UTC') AT TIME ZONE z.name AS started,
                         (v.ended_at AT TIME ZONE 'UTC') AT TIME ZONE z.name AS ended
                  FROM public.visits v WHERE #{@active}
                  ORDER BY v.started_at DESC, v.id DESC LIMIT 5) r),
         z.name
  FROM public.places p
  CROSS JOIN z
  WHERE p.id = $1 AND p.user_id = $2
  """

  def load(user, id, repo \\ Dawarich.Repo) do
    settings = Dawarich.UserSettings.get(user)

    with true <- PlaceList.settings?(Dawarich.UserSettings.get(user)),
         [[id, name, note, city, country, source, locked, count, minutes, tags, visits, zone]]
         when source in 0..2 or is_nil(source) <-
           UserTimeZone.query!(@sql, [id, user.id], settings, repo).rows,
         true <- TripSettings.zone?(settings, zone) do
      {:ok,
       %{
         id: id,
         name: name,
         note: note,
         city: city,
         country: country,
         source: if(source != nil, do: Enum.at(@sources, source)),
         locked: locked,
         visit_count: count,
         total_minutes: minutes,
         tags: Enum.map(tags, fn [n, i, c] -> %{name: n, icon: i, color: c} end),
         visits: Enum.map(visits, &visit/1)
       }}
    else
      _ -> :rails
    end
  end

  defp visit([name, duration, started, ended]),
    do: %{name: name, duration: duration, started: local(started), ended: local(ended)}

  defp local(text), do: NaiveDateTime.from_iso8601!(text)
end

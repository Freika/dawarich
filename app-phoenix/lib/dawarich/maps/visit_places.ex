defmodule Dawarich.Maps.VisitPlaces do
  @moduledoc false
  alias Dawarich.{Maps, Repo}
  alias Dawarich.Maps.{Entities, VisitEditing}
  alias Dawarich.PlacesApi.{Nearby, Search}

  @coords "SELECT COALESCE(ST_Y(p.lonlat::geometry), a.latitude::float8, ST_Y(c.lonlat::geometry)), COALESCE(ST_X(p.lonlat::geometry), a.longitude::float8, ST_X(c.lonlat::geometry)) FROM visits v LEFT JOIN places p ON p.id=v.place_id LEFT JOIN areas a ON a.id=v.area_id LEFT JOIN LATERAL (SELECT pl.lonlat FROM place_visits pv JOIN places pl ON pl.id=pv.place_id WHERE pv.visit_id=v.id ORDER BY pl.id LIMIT 1) c ON true WHERE v.id=$1 AND v.user_id=$2 AND v.deleted_at IS NULL"

  def search(scope, visit_id, query) do
    Maps.with_actor(scope, fn actor ->
      with {:ok, lat, lon} <- origin(actor, visit_id),
           {:ok, 200, body} <-
             Search.run(actor, %{
               "lat" => to_string(lat),
               "lon" => to_string(lon),
               "radius" => "1.0",
               "q" => query
             }) do
        places = Enum.map(body["places"], &Map.put(&1, "distance_m", meters(&1, lat, lon)))
        {:ok, %{"places" => places, "areas" => body["areas"], "origin" => [lat, lon]}}
      else
        {:error, reason} -> {:error, reason}
        _ -> {:error, :unavailable}
      end
    end)
  end

  def select(scope, visit_id, "place", %{"id" => id}) when is_integer(id),
    do: VisitEditing.update(scope, visit_id, %{"place_id" => to_string(id)})

  def select(scope, visit_id, "place", %{"name" => _} = external) do
    Maps.with_actor(scope, fn actor ->
      attrs = Map.take(external, ~w(name latitude longitude osm_id osm_type city country street))
      now = DateTime.utc_now()

      with {:ok, zone} <- VisitEditing.zone_for(actor),
           {:ok, _} <-
             Dawarich.VisitsApi.SelectPlace.call(actor.id, visit_id, attrs, zone, now, Repo) do
        :ok
      else
        {:error, reason} when is_atom(reason) -> {:error, reason}
        _ -> {:error, :unavailable}
      end
    end)
  end

  def select(scope, visit_id, "area", %{"id" => id}) when is_integer(id),
    do:
      VisitEditing.update(scope, visit_id, %{"area_id" => to_string(id), "status" => "confirmed"})

  def select(scope, visit_id, "create", %{"name" => name, "origin" => [lat, lon]}) do
    attrs = %{"name" => name, "latitude" => to_string(lat), "longitude" => to_string(lon)}

    with {:ok, place} <- Entities.save_place(scope, nil, attrs) do
      VisitEditing.update(scope, visit_id, %{
        "place_id" => to_string(place),
        "name" => name,
        "status" => "confirmed"
      })
    end
  end

  def select(_scope, _visit_id, _kind, _item), do: {:error, :not_found}

  defp origin(actor, visit_id) do
    case Repo.query!(@coords, [visit_id, actor.id]).rows do
      [[lat, lon]] when is_number(lat) and is_number(lon) -> {:ok, lat, lon}
      _ -> {:error, :not_found}
    end
  end

  defp meters(place, lat, lon) do
    case Nearby.distance(place, lat, lon) do
      km when is_number(km) -> round(km * 1000)
      _ -> nil
    end
  end
end

defmodule Dawarich.MapApi.PrivacyZones do
  @moduledoc false
  alias Dawarich.Repo

  def fetch(user) do
    tags =
      Repo.query!(
        "SELECT id,name,icon,color,privacy_radius_meters FROM tags WHERE user_id=$1 AND privacy_radius_meters IS NOT NULL ORDER BY id",
        [user.id]
      ).rows

    ids = Enum.map(tags, &hd/1)

    places =
      Repo.query!(
        "SELECT g.tag_id,p.id,p.name,coalesce(p.latitude::float8,0),coalesce(p.longitude::float8,0) FROM taggings g JOIN places p ON p.id=g.taggable_id WHERE g.taggable_type='Place' AND g.tag_id=ANY($1) ORDER BY g.id",
        [ids]
      ).rows
      |> Enum.group_by(&hd/1, fn [_tag, id, name, lat, lng] ->
        %{id: id, name: name, latitude: lat, longitude: lng}
      end)

    Enum.map(tags, fn [id, name, icon, color, radius] ->
      %{
        tag_id: id,
        tag_name: name,
        tag_icon: icon,
        tag_color: color,
        radius_meters: radius,
        places: Map.get(places, id, [])
      }
    end)
  end

  def term(zones),
    do:
      Enum.map(zones, fn zone ->
        {:object,
         for(
           key <- ~w(tag_id tag_name tag_icon tag_color radius_meters places)a,
           do: {Atom.to_string(key), zone[key]}
         )}
      end)
end

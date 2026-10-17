defmodule Dawarich.UserData.Export.Visits do
  @moduledoc false
  alias Dawarich.UserData.Export.{Monthly, Serializer}

  def write(repo, user, dir, context) do
    Monthly.write(
      repo,
      user,
      "visits",
      dir,
      context,
      ~w(place_id import_id),
      Monthly.timestamp_month("started_at"),
      fn id, pairs ->
        rows =
          repo.query!(
            "SELECT p.name,COALESCE(ST_Y(p.lonlat::geometry),p.latitude::float8,0.0),COALESCE(ST_X(p.lonlat::geometry),p.longitude::float8,0.0),p.source FROM visits v JOIN places p ON p.id=v.place_id AND p.user_id=$2 WHERE v.id=$1 AND v.user_id=$2",
            [id, user]
          ).rows

        ref =
          case rows do
            [] ->
              nil

            [[name, lat, lon, source]] ->
              %Jason.OrderedObject{
                values: [
                  {"name", name},
                  {"latitude", Dawarich.ReleaseMigrations.Effects.Support.RubyFloat.to_s(lat)},
                  {"longitude", Dawarich.ReleaseMigrations.Effects.Support.RubyFloat.to_s(lon)},
                  {"source", Serializer.value("places", "source", "int4", source)}
                ]
              }
          end

        pairs ++ [{"place_reference", ref}]
      end
    )
  end
end

defmodule Dawarich.Mcp.LatestLocation do
  @moduledoc false
  alias Dawarich.{RailsTime, Repo}
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias Dawarich.Tiles.Http

  def fetch(user) do
    {scope, args} = Http.point_scope(user, %{}, nil)

    RailsTime.with_zone(user.timezone, fn ->
      rows =
        Repo.query!(
          "SELECT p.id, ST_Y(p.lonlat::geometry), ST_X(p.lonlat::geometry), #{RailsTime.sql("to_timestamp(p.timestamp) AT TIME ZONE 'UTC'", 0)}, coalesce(p.country_name, ''), p.velocity, p.tracker_id FROM points p WHERE #{scope} AND (p.anomaly = false OR p.anomaly IS NULL) ORDER BY p.timestamp DESC LIMIT 1",
          args
        ).rows

      point =
        case rows do
          [] ->
            nil

          [[id, lat, lon, recorded, country, velocity, tracker]] ->
            {:object,
             [
               {"id", id},
               {"latitude", lat},
               {"longitude", lon},
               {"recorded_at", recorded},
               {"country_name", country},
               {"velocity", if(velocity in [nil, ""], do: nil, else: Ruby.to_f(velocity))},
               {"tracker_id", tracker}
             ]}
        end

      {:ok, {:object, [{"point", point}]}}
    end)
  end
end

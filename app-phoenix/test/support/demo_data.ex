defmodule Dawarich.Test.DemoData do
  @moduledoc false
  import Plug.Conn
  alias Dawarich.{Accounts, Repo}
  alias Dawarich.Test.RailsUser
  alias DawarichWeb.RailsCsrf

  def fixtures do
    points = %{
      "seed_date" => "2026-05-28T00:00:00Z",
      "features" =>
        for {lon, index} <- [{13.4, 0}, {13.41, 1}, {14.4, 2}] do
          %{
            "properties" => %{
              "latitude" => 52.5,
              "longitude" => lon,
              "timestamp" => 1_779_926_400 - 86_400 + index * 60,
              "altitude" => 42,
              "velocity" => "5",
              "accuracy" => 10,
              "vertical_accuracy" => 12,
              "battery" => 90,
              "battery_status" => 1
            }
          }
        end
    }

    derivatives = %{
      "tags" => [%{"key" => "home", "name" => "home", "icon" => "H", "color" => "#abc123"}],
      "places" => [
        %{
          "key" => "home",
          "name" => "Home",
          "lat" => 52.5,
          "lon" => 13.4,
          "tags" => ["home"],
          "geodata" => %{"city" => "Berlin"}
        }
      ],
      "visits" => [
        %{
          "place_key" => "home",
          "starts_offset_seconds" => -86400,
          "ends_offset_seconds" => -85800,
          "status" => "suggested",
          "alternates" => ["home"]
        }
      ],
      "trip" => %{
        "name" => "Demo trip",
        "starts_offset_seconds" => -86400,
        "ends_offset_seconds" => -85800,
        "distance_meters" => 1000,
        "notes" => "Synthetic trip"
      },
      "stats_daily" => [%{"day_offset" => -1, "distance_meters" => 1000, "in_prague" => true}],
      "tracks" => [
        %{
          "starts_offset_seconds" => -86400,
          "ends_offset_seconds" => -85800,
          "mode" => "walk",
          "avg_speed_kmh" => 5,
          "distance_meters" => 1000,
          "duration_seconds" => 600,
          "path_coordinates" => [[52.5, 13.4], [52.5, 13.41]]
        }
      ]
    }

    [points: points, derivatives: derivatives, now: ~U[2026-03-30 12:00:00Z]]
  end

  def request(id, method, params \\ %{}) do
    session = RailsUser.session(id)

    Plug.Test.conn(method, "/settings/onboarding/demo_data")
    |> put_req_header("content-type", "application/x-www-form-urlencoded")
    |> assign(:api_params, Map.put(params, "authenticity_token", RailsCsrf.masked_token(session)))
    |> assign(:api_query, %{})
    |> assign(:rails_session, session)
    |> assign(:current_user, Accounts.get(id))
  end

  def fail_visits do
    Repo.query!(
      "CREATE FUNCTION public.demo_visit_failure() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'synthetic visit failure'; END $$",
      [],
      log: false
    )

    Repo.query!(
      "CREATE TRIGGER demo_visit_failure BEFORE INSERT ON visits FOR EACH ROW EXECUTE FUNCTION public.demo_visit_failure()",
      [],
      log: false
    )
  end

  def real_point(id, timestamp) do
    Repo.query!(
      "INSERT INTO points (user_id,timestamp,lonlat,created_at,updated_at) VALUES ($1,$2,ST_SetSRID(ST_MakePoint(13.4,52.5),4326),now(),now()) RETURNING id",
      [id, timestamp],
      log: false
    ).rows
    |> hd()
    |> hd()
  end
end

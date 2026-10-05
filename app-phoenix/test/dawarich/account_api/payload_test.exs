defmodule Dawarich.AccountApi.PayloadTest do
  use Dawarich.DataCase, async: true
  alias Dawarich.AccountApi.Payload
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  @moduletag api_public_only: true

  @tag :account_defaults
  test "me reproduces settings defaults and selfhosted feature map" do
    id = user!(%{settings: %{"timezone" => "UTC"}})
    {:ok, term} = Payload.read(id)
    body = term |> Ruby.json() |> IO.iodata_to_binary() |> Jason.decode!()

    assert body["user"]["settings"] == %{
             "timezone" => "UTC",
             "maps" => %{"distance_unit" => "km"},
             "fog_of_war_meters" => 50,
             "meters_between_routes" => 500,
             "preferred_map_layer" => "OpenStreetMap",
             "speed_colored_routes" => false,
             "points_rendering_mode" => "raw",
             "minutes_between_routes" => 30,
             "time_threshold_minutes" => 30,
             "merge_threshold_minutes" => 15,
             "live_map_enabled" => true,
             "route_opacity" => 0.6,
             "immich_url" => nil,
             "photoprism_url" => nil,
             "visits_suggestions_enabled" => true,
             "speed_color_scale" => nil,
             "fog_of_war_threshold" => 50,
             "globe_projection" => true
           }

    assert body["features"]["family"] == true
    assert is_boolean(body["features"]["reverse_geocoding"])
  end

  @tag :account_malformed
  test "malformed account settings replay without changing rows" do
    for settings <- [
          %{"timezone" => true},
          %{"timezone" => "UTC", "fog_of_war_meters" => %{}},
          %{"timezone" => "UTC", "route_opacity" => false}
        ] do
      id = user!(%{settings: settings})
      before = Repo.query!("SELECT row_to_json(u)::text FROM users u WHERE id=$1", [id]).rows
      assert {:replay, _} = Payload.read(id)

      assert Repo.query!("SELECT row_to_json(u)::text FROM users u WHERE id=$1", [id]).rows ==
               before
    end
  end
end

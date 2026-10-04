defmodule DawarichWeb.MapDataRoutesTest do
  use ExUnit.Case, async: true

  alias DawarichWeb.Router

  test "API extraction preserves existing methods pipelines slices and gates" do
    actual =
      for route <- Router.__routes__(), String.starts_with?(route.path, "/api/") do
        {route.verb, route.path, pipelines(route), route.metadata[:slice],
         route.metadata[:rails_gate]}
      end

    assert actual == [
             {:post, "/api/v1/users/exist", [:api_manager], :api_account, nil},
             {:get, "/api/v1/users/me", [:api_account], :api_account, nil},
             {:post, "/api/v1/users/me/two_factor/setup", [:api_account], :api_account, nil},
             {:post, "/api/v1/users/me/two_factor/confirm", [:api_account], :api_account, nil},
             {:post, "/api/v1/users/me/two_factor/backup_codes", [:api_account], :api_account,
              nil},
             {:delete, "/api/v1/users/me/two_factor", [:api_account], :api_account, nil},
             {:post, "/api/v1/visits/merge", [:api_visits], :api_visits, nil},
             {:post, "/api/v1/visits/bulk_update", [:api_visits], :api_visits, nil},
             {:post, "/api/v1/visits/batch", [:api_visits], :api_visits, nil},
             {:get, "/api/v1/visits", [:api_visits], :api_visits, nil},
             {:post, "/api/v1/visits", [:api_visits], :api_visits, nil},
             {:get, "/api/v1/visits/:id", [:api_visits], :api_visits, nil},
             {:patch, "/api/v1/visits/:id", [:api_visits], :api_visits, nil},
             {:put, "/api/v1/visits/:id", [:api_visits], :api_visits, nil},
             {:delete, "/api/v1/visits/:id", [:api_visits], :api_visits, nil},
             {:get, "/api/v1/visits/:id/possible_places", [:api_visits], :api_visits, nil},
             {:post, "/api/v1/visits/:id/select_place", [:api_visits], :api_visits, nil},
             {:get, "/api/v1/notes", [:api_notes], :api_notes, nil},
             {:post, "/api/v1/notes", [:api_notes], :api_notes, nil},
             {:get, "/api/v1/notes/:id", [:api_notes], :api_notes, nil},
             {:patch, "/api/v1/notes/:id", [:api_notes], :api_notes, nil},
             {:put, "/api/v1/notes/:id", [:api_notes], :api_notes, nil},
             {:delete, "/api/v1/notes/:id", [:api_notes], :api_notes, nil},
             {:get, "/api/v1/shared/:id/trip", [:api_shared], :api_shared, nil},
             {:get, "/api/v1/shared/:id/points", [:api_shared], :api_shared, nil},
             {:get, "/api/v1/shared/:id/route", [:api_shared], :api_shared, nil},
             {:get, "/api/v1/shared/:id/photos", [:api_shared], :api_shared, nil},
             {:get, "/api/v1/shared/:id/photos/:photo_id/thumbnail", [:api_shared], :api_shared,
              nil},
             {:post, "/api/v1/points", [:api_ingest], :ingest, nil},
             {:post, "/api/v1/overland/batches", [:api_ingest], :ingest, nil},
             {:post, "/api/v1/owntracks/points", [:api_ingest], :ingest, nil},
             {:post, "/api/v1/traccar/points", [:api_ingest], :ingest, nil},
             {:get, "/api/v1/plan", [:api_foundation], :api_foundation, nil},
             {:get, "/api/v1/stats", [:api_stats], :api_stats, nil},
             {:get, "/api/v1/insights", [:api_stats], :api_stats, nil},
             {:get, "/api/v1/insights/details", [:api_stats], :api_stats, nil},
             {:get, "/api/v1/residency", [:api_stats], :api_stats, nil},
             {:get, "/api/v1/digests", [:api_stats], :api_stats, nil},
             {:get, "/api/v1/digests/:year", [:api_stats], :api_stats, nil},
             {:get, "/api/v1/countries/visited_cities", [:api_stats], :api_stats, nil},
             {:get, "/api/v1/flights", [:api_stats], :api_stats, nil},
             {:get, "/api/v1/points", [:api_stats], :api_map_reads, nil},
             {:get, "/api/v1/tracks", [:api_stats], :api_map_reads, nil},
             {:get, "/api/v1/tracks/:id", [:api_stats], :api_map_reads, nil},
             {:get, "/api/v1/tracks/:track_id/points", [:api_stats], :api_map_reads, nil},
             {:get, "/api/v1/places", [:api_places], :api_places, nil},
             {:post, "/api/v1/places", [:api_places], :api_places, nil},
             {:get, "/api/v1/places/:id", [:api_places], :api_places, nil},
             {:patch, "/api/v1/places/:id", [:api_places], :api_places, nil},
             {:put, "/api/v1/places/:id", [:api_places], :api_places, nil},
             {:delete, "/api/v1/places/:id", [:api_places], :api_places, nil},
             {:get, "/api/v1/families/locations", [:api_stats], :api_family, nil},
             {:get, "/api/v1/families/locations/history", [:api_stats], :api_family, nil},
             {:get, "/api/v1/families/mine", [:api_stats], :api_family, nil},
             {:patch, "/api/v1/families/sharing", [:api_stats], :api_family, nil},
             {:put, "/api/v1/families/sharing", [:api_stats], :api_family, nil},
             {:post, "/api/v1/families/location_requests", [:api_stats], :api_family, nil},
             {:post, "/api/v1/families/location_requests/:id/accept", [:api_stats], :api_family,
              nil},
             {:post, "/api/v1/families/location_requests/:id/decline", [:api_stats], :api_family,
              nil},
             {:get, "/api/v1/locations", [:api_locations_photos], :api_locations_photos, nil},
             {:get, "/api/v1/photos/:id/thumbnail", [:api_locations_photos],
              :api_locations_photos, nil},
             {:get, "/api/v1/photos/:id/thumbnail.jpg", [:api_locations_photos],
              :api_locations_photos, nil}
           ]
  end

  test "existing page frame and sharing routes retain their pipelines" do
    for {verb, path, pipelines, gate} <- [
          {:get, "/map", [:browser, :rails_user], nil},
          {:get, "/map/v2", [:browser, :rails_user], nil},
          {:get, "/places", [:browser, :rails_user], {DawarichWeb.PlacesGate, :index?}},
          {:get, "/places/:id", [:rails_frame], {DawarichWeb.PlacesGate, :drawer?}},
          {:get, "/map/timeline_feeds", [:rails_frame], {DawarichWeb.MapFramesGate, :feed?}},
          {:get, "/map/timeline_feeds/calendar", [:rails_frame],
           {DawarichWeb.MapFramesGate, :calendar?}},
          {:get, "/map/residency", [:rails_frame], {DawarichWeb.MapFramesGate, :residency?}},
          {:get, "/map/timeline_feeds/:id/track_info", [:rails_frame],
           {DawarichWeb.MapFramesGate, :track?}},
          {:get, "/s/:id", [:sharing], {DawarichWeb.SharingGate, :show?}},
          {:post, "/s/:id/unlock", [:sharing_unlock], {DawarichWeb.SharingGate, :unlock?}}
        ] do
      route = Enum.find(Router.__routes__(), &(&1.verb == verb and &1.path == path))
      assert pipelines(route) == pipelines
      assert route.metadata[:rails_gate] == gate
    end
  end

  defp pipelines(route) do
    Phoenix.Router.route_info(
      Router,
      route.verb |> Atom.to_string() |> String.upcase(),
      route.path,
      "localhost"
    ).pipe_through
  end
end

defmodule DawarichWeb.A8Routes do
  @moduledoc false
  defmacro a8_routes do
    quote do
      pipeline :a8_action do
        plug DawarichWeb.HostAuthorization
        plug DawarichWeb.ForceSSL
        plug DawarichWeb.RateLimit
        plug DawarichWeb.RailsAuth
        plug DawarichWeb.A8Request
        plug DawarichWeb.Locale
        plug DawarichWeb.RailsHeaders
      end

      scope "/" do
        pipe_through :a8_action

        post "/trips/:trip_id/notes", DawarichWeb.TripNoteActions, :create

        patch "/trips/:trip_id/notes/:id", DawarichWeb.TripNoteActions, :update

        put "/trips/:trip_id/notes/:id", DawarichWeb.TripNoteActions, :update

        delete "/trips/:trip_id/notes/:id", DawarichWeb.TripNoteActions, :destroy

        post "/trips/:trip_id/notes/:id", DawarichWeb.TripNoteActions, :member

        post "/trips", DawarichWeb.TripActions, :create

        post "/trips/:id/recalculate", DawarichWeb.TripActions, :recalculate

        post "/trips/:id/export", DawarichWeb.TripActions, :export

        patch "/trips/:id", DawarichWeb.TripActions, :update

        put "/trips/:id", DawarichWeb.TripActions, :update

        delete "/trips/:id", DawarichWeb.TripActions, :destroy

        post "/trips/:id", DawarichWeb.TripActions, :member

        post "/places", DawarichWeb.PlaceActions, :create

        patch "/places/:id", DawarichWeb.PlaceActions, :update

        put "/places/:id", DawarichWeb.PlaceActions, :update

        delete "/places/:id", DawarichWeb.PlaceActions, :destroy

        post "/places/:id", DawarichWeb.PlaceActions, :member

        post "/route_videos", DawarichWeb.RouteVideoActions, :create

        delete "/route_videos/:id", DawarichWeb.RouteVideoActions, :destroy

        post "/route_videos/:id", DawarichWeb.RouteVideoActions, :destroy

        patch "/visits/bulk_update", DawarichWeb.VisitActions, :bulk_update

        post "/visits/bulk_update", DawarichWeb.VisitActions, :bulk_update

        delete "/visits/bulk_destroy", DawarichWeb.VisitActions, :bulk_destroy

        post "/visits/bulk_destroy", DawarichWeb.VisitActions, :bulk_destroy

        post "/visits/merge", DawarichWeb.VisitActions, :merge

        patch "/visits/:id", DawarichWeb.VisitActions, :update

        put "/visits/:id", DawarichWeb.VisitActions, :update

        delete "/visits/:id", DawarichWeb.VisitActions, :destroy

        post "/visits/:id", DawarichWeb.VisitActions, :member
      end

      pipeline :a8_public do
        plug DawarichWeb.HostAuthorization
        plug DawarichWeb.ForceSSL
        plug DawarichWeb.RateLimit
        plug DawarichWeb.RailsHeaders
      end

      scope "/" do
        pipe_through :a8_public

        get "/visits", DawarichWeb.VisitsNavigation, :index, metadata: %{native_page: true}
      end
    end
  end
end

defmodule DawarichWeb.NativeM6Routes do
  @moduledoc false
  defmacro native_m6_routes do
    quote do
      pipeline :native_map_retired do
        plug DawarichWeb.HostAuthorization
        plug DawarichWeb.ForceSSL
        plug DawarichWeb.RateLimit
      end

      scope "/" do
        pipe_through :native_map_retired

        for path <-
              ~w(/map/timeline_feeds /map/timeline_feeds/calendar /map/timeline_feeds/:retired_id/track_info /tracks/:retired_track_id/segments /tracks/:retired_track_id/segments/:retired_id /points/:retired_id/address),
            method <- [:get, :post, :put, :patch, :delete] do
          match method, path, DawarichWeb.NativeMapRetired, :gone, metadata: %{retired: true}
        end
      end

      pipeline :native_m6_browser do
        plug DawarichWeb.HostAuthorization
        plug DawarichWeb.ForceSSL
        plug DawarichWeb.RateLimit
        plug :fetch_query_params
        plug DawarichWeb.NativeM6Envelope
        plug :accepts, ["html"]
        plug DawarichWeb.RailsAuth
        plug :phoenix_session
        plug :fetch_session
        plug :fetch_live_flash
        plug DawarichWeb.Locale
        plug DawarichWeb.LayoutAssigns
        plug :put_root_layout, html: {DawarichWeb.Layouts, :native_root}
        plug :protect_from_forgery
        plug DawarichWeb.RailsHeaders
      end

      scope "/" do
        pipe_through :native_m6_browser

        for path <- ~w(/map /map/v2), method <- [:post, :put, :patch, :delete] do
          match method, path, DawarichWeb.NativeM6Envelope, [], metadata: %{retired: true}
        end
      end

      scope "/" do
        pipe_through :native_m6_browser

        live_session :native_m6_public,
          session: {DawarichWeb.PublicMapAuth, :live_session, []},
          root_layout: {DawarichWeb.Layouts, :native_root},
          layout: false do
          live "/s/:id", DawarichWeb.PublicMapLive, :show,
            container: {:div, class: "contents"},
            metadata: %{retired: true}
        end
      end

      scope "/" do
        pipe_through [:native_m6_browser, :rails_user]

        live_session :native_m6,
          session: {DawarichWeb.MapLiveAuth, :live_session, []},
          root_layout: {DawarichWeb.Layouts, :native_root},
          layout: false do
          for path <- ~w(/map.html /map/v2.html) do
            live path, DawarichWeb.MapLive.Native, :index,
              container: {:div, class: "contents"},
              metadata: %{retired: true}
          end

          live "/map", DawarichWeb.MapLive.Native, :index,
            container: {:div, class: "contents"},
            metadata: %{retired: true}

          live "/map/v2", DawarichWeb.MapLive.Native, :index,
            container: {:div, class: "contents"},
            metadata: %{retired: true}

          live "/trips/:id", DawarichWeb.TripsLive.NativeMap, :show,
            container: {:div, class: "contents"},
            metadata: %{retired: true}
        end
      end
    end
  end
end

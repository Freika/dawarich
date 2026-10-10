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

      scope "/" do
        pipe_through :browser

        live_session :native_m6_public,
          session: {DawarichWeb.PublicMapAuth, :live_session, []},
          root_layout: {DawarichWeb.Layouts, :native_root},
          layout: false do
          live "/s/:id", DawarichWeb.PublicMapLive, :show, container: {:div, class: "contents"}
        end
      end

      scope "/" do
        pipe_through [:browser, :rails_user]

        live_session :native_m6,
          session: {DawarichWeb.MapLiveAuth, :live_session, []},
          root_layout: {DawarichWeb.Layouts, :native_root},
          layout: false do
          live "/map", DawarichWeb.MapLive.Native, :index, container: {:div, class: "contents"}
          live "/map/v2", DawarichWeb.MapLive.Native, :index, container: {:div, class: "contents"}
        end
      end
    end
  end
end

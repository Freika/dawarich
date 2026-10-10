defmodule DawarichWeb.NativeSharingRoutes do
  @moduledoc false
  defmacro pages do
    quote do
      scope "/" do
        pipe_through [:browser, :native_family_user]
        get "/native/sharing/phrase", DawarichWeb.SharingSecretReveal, :generate
        get "/native/sharing/:id/:field", DawarichWeb.SharingSecretReveal, :show

        live_session :native_sharing,
          session: {DawarichWeb.NativeSharingAuth, :live_session, []},
          on_mount: {DawarichWeb.NativeSharingAuth, :require_user},
          root_layout: {DawarichWeb.Layouts, :native_root},
          layout: {DawarichWeb.Layouts, :app} do
          live "/stats/:year/:month/sharing", DawarichWeb.SharingLive.Index, :month,
            metadata: %{native_ui: true}

          live "/digests/:year/sharing", DawarichWeb.SharingLive.Index, :digest,
            metadata: %{native_ui: true}

          live "/achievements/:key/sharing", DawarichWeb.SharingLive.Index, :achievement,
            metadata: %{native_ui: true}

          live "/share_links/hub", DawarichWeb.SharingLive.Index, :hub,
            metadata: %{native_ui: true}

          live "/share_links/live/new", DawarichWeb.SharingLive.Index, :live,
            metadata: %{native_ui: true}

          live "/share_links/timeline/new", DawarichWeb.SharingLive.Index, :timeline,
            metadata: %{native_ui: true}

          live "/trips/:trip_id/share_link/new", DawarichWeb.SharingLive.Index, :trip,
            metadata: %{native_ui: true}

          live "/tracks/:track_id/share_link/new", DawarichWeb.SharingLive.Index, :track,
            metadata: %{native_ui: true}
        end
      end
    end
  end
end

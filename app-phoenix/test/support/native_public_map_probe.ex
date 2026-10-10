defmodule Dawarich.Test.NativePublicMapProbeRouter do
  use Phoenix.Router
  import Phoenix.LiveView.Router

  pipeline :public_probe do
    plug(:fetch_query_params)
    plug(DawarichWeb.RailsAuth)
    plug(DawarichWeb.Locale)
    plug(DawarichWeb.LayoutAssigns)
    plug(:fetch_live_flash)
  end

  scope "/probe-public" do
    pipe_through(:public_probe)

    live_session :public_map_probe, session: {DawarichWeb.PublicMapAuth, :live_session, []} do
      live("/:id", DawarichWeb.PublicMapLive)
    end
  end
end

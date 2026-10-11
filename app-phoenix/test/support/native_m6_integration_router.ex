defmodule Dawarich.Test.NativeM6IntegrationRouter do
  use Phoenix.Router
  import Phoenix.LiveView.Router

  pipeline :map do
    plug DawarichWeb.RailsAuth
    plug :fetch_live_flash
  end

  scope "/" do
    pipe_through :map

    live_session :native_m6_integration,
      session: {DawarichWeb.MapLiveAuth, :live_session, []} do
      live "/map/v2", DawarichWeb.MapLive.Native
      live "/trips/:id", DawarichWeb.TripsLive.NativeMap
      live "/family", DawarichWeb.FamiliesLive.NativeMap
    end
  end
end

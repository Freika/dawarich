defmodule Dawarich.Test.TripsNativeRouter do
  use Phoenix.Router
  import Phoenix.LiveView.Router
  require DawarichWeb.TripsNativeRoutes

  pipeline :native_trips do
    plug :fetch_query_params
    plug DawarichWeb.RailsAuth
    plug Plug.Session, DawarichWeb.Endpoint.session_options()
    plug :fetch_session
    plug :fetch_live_flash
    plug DawarichWeb.Locale
    plug DawarichWeb.LayoutAssigns
  end

  scope "/" do
    pipe_through :native_trips
    DawarichWeb.TripsNativeRoutes.trips_native_routes()
  end
end

defmodule Dawarich.Test.TripsNativeUI do
  import Phoenix.LiveViewTest
  alias Dawarich.Test.{RailsUser, TripsNativeRouter}

  def get(user_id, path) do
    conn = Phoenix.ConnTest.build_conn(:get, path)

    conn =
      if user_id,
        do:
          Phoenix.ConnTest.put_req_cookie(
            conn,
            "_dawarich_session",
            RailsUser.cookie(RailsUser.session(user_id))
          ),
        else: conn

    conn
    |> Plug.Conn.put_private(:phoenix_endpoint, DawarichWeb.Endpoint)
    |> Plug.Conn.put_private(:live_view_connect_info, %{session: %{"rails_user_id" => user_id}})
    |> TripsNativeRouter.call(TripsNativeRouter.init([]))
  end

  def live_as(user_id, path), do: live(get(user_id, path))
end

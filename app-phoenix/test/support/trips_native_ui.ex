defmodule Dawarich.Test.TripsNativeRouter do
  use Phoenix.Router
  import Phoenix.LiveView.Router

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

    live_session :native_trips,
      session: {DawarichWeb.NativeAuth, :live_session, []},
      on_mount: {DawarichWeb.TripsNative.Access, :require_user},
      root_layout: {DawarichWeb.Layouts, :native_root},
      layout: {DawarichWeb.Layouts, :app} do
      live "/trips", DawarichWeb.NativeTripsLive.Index, :index
      live "/trips/new", DawarichWeb.NativeTripsLive.Form, :new
      live "/trips/:id/edit", DawarichWeb.NativeTripsLive.Form, :edit
      live "/trips/:id", DawarichWeb.NativeTripsLive.Show, :show
    end
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

    %{conn | secret_key_base: DawarichWeb.Endpoint.config(:secret_key_base)}
    |> Plug.Conn.put_private(:phoenix_endpoint, DawarichWeb.Endpoint)
    |> Plug.Conn.put_private(:live_view_connect_info, %{session: %{"rails_user_id" => user_id}})
    |> TripsNativeRouter.call(TripsNativeRouter.init([]))
  end

  def live_as(user_id, path), do: live(get(user_id, path))

  def not_found?(user_id, path) do
    get(user_id, path)
    false
  rescue
    error in Plug.Conn.WrapperError -> Plug.Exception.status(error.reason) == 404
  end
end

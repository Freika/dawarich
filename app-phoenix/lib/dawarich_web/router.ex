defmodule DawarichWeb.Router do
  use Phoenix.Router
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug DawarichWeb.HostAuthorization
    plug :accepts, ["html"]
    plug DawarichWeb.ForceSSL
    plug :fetch_query_params
    plug DawarichWeb.TurboVisit
    plug DawarichWeb.RailsAuth
    plug :phoenix_session
    plug :fetch_session
    plug :fetch_live_flash
    plug DawarichWeb.Locale
    plug DawarichWeb.LayoutAssigns
    plug :put_root_layout, html: {DawarichWeb.Layouts, :root}
    plug :protect_from_forgery
    plug DawarichWeb.RailsHeaders
  end

  pipeline :rails_user do
    plug DawarichWeb.RequireUser
  end

  scope "/notifications" do
    pipe_through [:browser, :rails_user]

    live_session :rails_pages,
      session: {DawarichWeb.RailsAuth, :live_session, []},
      on_mount: DawarichWeb.LiveAuth,
      root_layout: {DawarichWeb.Layouts, :root},
      layout: {DawarichWeb.Layouts, :app} do
      live "/", DawarichWeb.NotificationsLive.Index, :index, container: {:div, class: "contents"}
      live "/:id", DawarichWeb.NotificationsLive.Show, :show, container: {:div, class: "contents"}
    end
  end

  defp phoenix_session(conn, _opts) do
    opts =
      Keyword.put(
        DawarichWeb.Endpoint.session_options(),
        :secure,
        DawarichWeb.ForceSSL.enabled?()
      )

    Plug.Session.call(conn, Plug.Session.init(opts))
  end
end

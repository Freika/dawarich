defmodule DawarichWeb.Router do
  use Phoenix.Router
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug DawarichWeb.ForceSSL
    plug :phoenix_session
    plug :fetch_session
    plug :fetch_live_flash
    plug DawarichWeb.RailsAuth
    plug DawarichWeb.Locale
    plug DawarichWeb.LayoutAssigns
    plug :put_root_layout, html: {DawarichWeb.Layouts, :root}
    plug :protect_from_forgery
    plug DawarichWeb.RailsHeaders
  end

  if Application.compile_env(:dawarich, :reference_live, false) do
    scope "/phoenix/reference" do
      pipe_through :browser

      live_session :reference,
        session: {DawarichWeb.RailsAuth, :live_session, []},
        on_mount: DawarichWeb.LiveAuth,
        root_layout: {DawarichWeb.Layouts, :root},
        layout: {DawarichWeb.Layouts, :app} do
        live "/", DawarichWeb.ReferenceLive, :index, container: {:div, class: "contents"}
      end
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

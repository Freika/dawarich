defmodule Dawarich.Test.A10InsightsStrangler do
  import Plug.Conn
  def init(opts), do: opts

  def call(%{request_path: path} = conn, _opts) when path in ["/", "/insights/details"] do
    if DawarichWeb.InsightsGate.owned?(conn),
      do: Plug.Head.call(conn, []),
      else:
        conn
        |> DawarichWeb.RailsProxy.call(Application.fetch_env!(:dawarich, :rails_upstream))
        |> halt()
  end

  def call(conn, _opts), do: DawarichWeb.Strangler.call(conn, [])
end

defmodule Dawarich.Test.A10InsightsRouter do
  use Phoenix.Router
  import Phoenix.LiveView.Router

  pipeline :insights do
    plug DawarichWeb.HostAuthorization
    plug :accepts, ["html"]
    plug DawarichWeb.ForceSSL
    plug :fetch_query_params
    plug DawarichWeb.InsightsVisit
    plug DawarichWeb.RailsAuth
    plug :auth_restore
    plug :phoenix_session
    plug :fetch_session
    plug :fetch_live_flash
    plug DawarichWeb.Locale
    plug DawarichWeb.LayoutAssigns
    plug :put_root_layout, html: {DawarichWeb.Layouts, :root}
    plug :protect_from_forgery
    plug DawarichWeb.RailsHeaders
    plug DawarichWeb.InsightsFrame
    plug DawarichWeb.RequireUser
  end

  scope "/" do
    pipe_through :insights
    get "/", DawarichWeb.InsightsHome, :index

    live_session :a10_insights,
      session: {DawarichWeb.InsightsFrame, :live_session, []},
      on_mount: DawarichWeb.InsightsFrameAuth,
      layout: {DawarichWeb.Layouts, :app} do
      live "/insights/details", DawarichWeb.InsightsLive.Details, :index,
        container: {:div, class: "contents"}
    end
  end

  forward "/", DawarichWeb.Router
  defp auth_restore(conn, _opts), do: DawarichWeb.AuthRestore.call(conn, enabled: true)

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

defmodule Dawarich.Test.A10InsightsEndpoint do
  use Phoenix.Endpoint, otp_app: :dawarich

  @session_options [
    store: DawarichWeb.SessionStore,
    key: "_dawarich_phoenix",
    signing_salt: "dawarich phoenix session",
    encryption_salt: "dawarich phoenix session encryption",
    same_site: "Lax"
  ]
  socket "/phoenix/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: false

  plug Plug.Static, at: "/phoenix/js", from: {:phoenix, "priv/static"}, only: ~w(phoenix.mjs)

  plug Plug.Static,
    at: "/phoenix/js",
    from: {:phoenix_live_view, "priv/static"},
    only: ~w(phoenix_live_view.esm.js)

  plug Plug.Static, at: "/phoenix/js", from: {:dawarich, "priv/static/js"}, only: ~w(app.js)
  plug DawarichWeb.PublicFiles
  plug Dawarich.Test.A10InsightsStrangler
  plug Dawarich.Test.A10InsightsRouter
end

defmodule DawarichWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :dawarich

  @session_options [
    store: DawarichWeb.SessionStore,
    key: "_dawarich_phoenix",
    signing_salt: "dawarich phoenix session",
    encryption_salt: "dawarich phoenix session encryption",
    same_site: "Lax"
  ]

  def session_options, do: @session_options

  socket "/phoenix/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: false

  plug Plug.Static,
    at: "/phoenix/js",
    from: {:phoenix, "priv/static"},
    only: ~w(phoenix.mjs)

  plug Plug.Static,
    at: "/phoenix/js",
    from: {:phoenix_live_view, "priv/static"},
    only: ~w(phoenix_live_view.esm.js)

  plug Plug.Static,
    at: "/phoenix/js",
    from: {:dawarich, "priv/static/js"},
    only: ~w(app.js)

  plug DawarichWeb.PublicFiles
  plug DawarichWeb.Strangler
  plug DawarichWeb.Router
end

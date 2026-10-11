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

  socket "/phoenix/live", DawarichWeb.LiveSocket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: false

  plug DawarichWeb.RequestLogger
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint], log: false

  plug Plug.Static,
    at: "/phoenix/js",
    from: {:phoenix, "priv/static"},
    only: ~w(phoenix.mjs)

  plug Plug.Static,
    at: "/native",
    from: {:dawarich, "priv/static/native"},
    gzip: true

  plug Plug.Static,
    at: "/phoenix/js",
    from: {:phoenix_live_view, "priv/static"},
    only: ~w(phoenix_live_view.esm.js)

  plug DawarichWeb.PublicFiles
  plug DawarichWeb.Cors
  plug DawarichWeb.AuthGate
  plug DawarichWeb.Api.RequestFormat
  plug DawarichWeb.Api.MethodOverride
  plug DawarichWeb.DocumentAliases
  plug DawarichWeb.NativeRequest
  plug DawarichWeb.Api.Transport, :router
end

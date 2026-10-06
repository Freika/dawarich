defmodule DawarichWeb.Api.ClientSession do
  @moduledoc false
  import Plug.Conn

  def call(conn) do
    conn = DawarichWeb.RailsAuth.call(conn, [])

    client =
      List.first(get_req_header(conn, "x-dawarich-client")) || conn.assigns.api_params["client"]

    if client in ["ios", "android"] and conn.assigns.rails_session["dawarich_client"] != client do
      session =
        conn.assigns.rails_session
        |> Map.put("dawarich_client", client)
        |> Map.put_new_lazy("session_id", fn ->
          Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
        end)

      value =
        Dawarich.RailsCookies.encrypt(session, "_dawarich_session", Dawarich.RailsSecret.fetch())

      put_resp_cookie(conn, "_dawarich_session", value,
        path: "/",
        http_only: true,
        same_site: "Lax",
        secure: DawarichWeb.ForceSSL.enabled?()
      )
    else
      conn
    end
  end
end

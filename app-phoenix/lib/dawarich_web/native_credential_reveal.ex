defmodule DawarichWeb.NativeCredentialReveal do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  alias DawarichWeb.{RailsCsrf, RequestURL}

  def init(opts), do: opts

  def call(conn, kind) do
    user = conn.assigns[:current_user]
    token = List.first(get_req_header(conn, "x-csrf-token"))
    site = List.first(get_req_header(conn, "sec-fetch-site"))

    if user && site in [nil, "same-origin"] &&
         get_req_header(conn, "origin") in [[], [RequestURL.base(conn)]] &&
         RailsCsrf.valid?(conn.assigns[:rails_session] || %{}, token) do
      conn = put_resp_header(conn, "cache-control", "no-store")

      if kind == :key do
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(%{api_key: user.api_key}))
      else
        conn
        |> put_resp_content_type("image/svg+xml")
        |> send_resp(200, Dawarich.QrSvg.api_key(RequestURL.base(conn) <> "/", user.api_key, 3))
      end
    else
      conn |> send_resp(403, "") |> halt()
    end
  end
end

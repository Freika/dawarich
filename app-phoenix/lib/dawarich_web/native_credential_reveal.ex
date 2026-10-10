defmodule DawarichWeb.NativeCredentialReveal do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  alias DawarichWeb.{RailsCsrf, RequestURL}

  def init(opts), do: opts

  def call(conn, _opts) do
    user = conn.assigns[:current_user]
    token = List.first(get_req_header(conn, "x-csrf-token"))
    site = List.first(get_req_header(conn, "sec-fetch-site"))

    if user && site in [nil, "same-origin"] &&
         RailsCsrf.valid?(conn.assigns[:rails_session] || %{}, token) do
      conn
      |> put_resp_header("cache-control", "no-store")
      |> put_resp_content_type("image/svg+xml")
      |> send_resp(200, Dawarich.QrSvg.api_key(RequestURL.base(conn) <> "/", user.api_key, 3))
    else
      conn |> send_resp(403, "") |> halt()
    end
  end
end

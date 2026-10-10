defmodule DawarichWeb.FamilyInvitationReveal do
  @moduledoc false
  import Plug.Conn
  alias DawarichWeb.{RailsCsrf, RequestURL}
  def init(action), do: action

  def call(conn, action) do
    site = List.first(get_req_header(conn, "sec-fetch-site"))
    token = List.first(get_req_header(conn, "x-csrf-token"))
    csrf = action == :view or RailsCsrf.valid?(conn.assigns[:rails_session] || %{}, token)
    conn = put_resp_header(conn, "cache-control", "no-store")

    with true <- site in [nil, "same-origin"] and csrf,
         value when is_binary(value) and byte_size(value) <= 19 <- conn.path_params["id"],
         {id, ""} when id > 0 and id <= 9_223_372_036_854_775_807 <- Integer.parse(value),
         {:ok, capability} <-
           Dawarich.Families.reveal_invitation(
             Dawarich.Accounts.Scope.for_user(conn.assigns.current_user, conn.assigns.locale),
             id
           ) do
      path = "/invitations/" <> capability

      if action == :view,
        do: conn |> put_resp_header("location", path) |> send_resp(302, "") |> halt(),
        else:
          conn
          |> put_resp_content_type("text/plain")
          |> send_resp(200, RequestURL.base(conn) <> path)
          |> halt()
    else
      false -> conn |> send_resp(403, "") |> halt()
      _ -> conn |> send_resp(404, "") |> halt()
    end
  end
end

defmodule DawarichWeb.SharingSecretReveal do
  @moduledoc false
  import Plug.Conn
  def init(action), do: action

  def call(conn, action) do
    conn = put_resp_header(conn, "cache-control", "no-store")
    scope = Dawarich.Accounts.Scope.for_user(conn.assigns.current_user, conn.assigns.locale)

    field =
      case conn.path_params["field"] do
        "phrase" -> :phrase
        "url" -> :url
        _ -> nil
      end

    with true <- List.first(get_req_header(conn, "sec-fetch-site")) in [nil, "same-origin"],
         true <-
           DawarichWeb.RailsCsrf.valid?(
             conn.assigns[:rails_session] || %{},
             List.first(get_req_header(conn, "x-csrf-token"))
           ),
         {:ok, text} <- reveal(scope, conn.path_params, field, action) do
      value = if field == :url, do: DawarichWeb.RequestURL.base(conn) <> text, else: text
      conn |> put_resp_content_type("text/plain") |> send_resp(200, value) |> halt()
    else
      false -> conn |> send_resp(403, "") |> halt()
      _ -> conn |> send_resp(404, "") |> halt()
    end
  end

  defp reveal(scope, _, _, :generate), do: Dawarich.Sharing.generate_phrase(scope)

  defp reveal(scope, params, field, _),
    do:
      Dawarich.Sharing.reveal(
        scope,
        %{type: :shared, owner_id: scope.user.id, id: params["id"]},
        field
      )
end

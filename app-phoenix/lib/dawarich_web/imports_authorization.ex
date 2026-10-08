defmodule DawarichWeb.ImportsAuthorization do
  @moduledoc false
  import Plug.Conn
  alias Dawarich.Imports.UiRecords
  alias DawarichWeb.{ImportsContext, Locale, RailsHeaders, RailsRedirect, RailsSession, Translate}

  def call(%{path_info: ["imports", id | _], assigns: %{current_user: %{id: user_id}}} = conn)
      when id != "new" do
    if Dawarich.Standalone.enabled?() do
      case UiRecords.get(ImportsContext.repo(), user_id, id) do
        {:ok, _} -> conn
        {:error, :not_found} -> refuse(conn, id)
      end
    else
      conn
    end
  end

  def call(conn), do: conn

  defp refuse(conn, id) do
    case Integer.parse(id) do
      {id, ""} when id > 0 and id <= 9_223_372_036_854_775_807 ->
        if ImportsContext.repo().query!("SELECT 1 FROM imports WHERE id=$1", [id], log: false).rows ==
             [],
           do: missing(conn),
           else: denied(conn)

      _ ->
        missing(conn)
    end
  end

  defp denied(conn) do
    locale = Locale.resolve(nil, conn.assigns.current_user, conn.assigns.rails_session)

    message =
      Translate.t(
        locale,
        "controllers.application.you_are_not_authorized_to_perform_this_action",
        %{}
      )

    conn
    |> RailsSession.stage(%{"flash" => %{"discard" => [], "flashes" => %{"alert" => message}}})
    |> RailsHeaders.call([])
    |> delete_resp_header("x-dawarich-handler")
    |> put_resp_header("location", RailsRedirect.back(conn))
    |> put_resp_header("cache-control", "no-cache")
    |> put_resp_content_type("text/html")
    |> send_resp(303, "")
    |> halt()
  end

  defp missing(conn), do: DawarichWeb.RailsErrors.respond(conn, 404)
end

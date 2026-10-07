defmodule DawarichWeb.ExportsDelete do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  alias DawarichWeb.{Locale, RailsSession, RequestURL, Translate}

  def init(action), do: action

  def call(conn, :delete) do
    user = conn.assigns.current_user

    case Dawarich.Exports.Delete.call(Dawarich.Repo, user.id, conn.path_params["id"]) do
      {:ok, :deleted} ->
        locale = Locale.resolve(nil, user, conn.assigns.rails_session)
        notice = Translate.t(locale, "controllers.exports.export_was_successfully_destroyed", %{})

        conn
        |> RailsSession.stage(%{
          "flash" => %{"discard" => [], "flashes" => %{"notice" => notice}}
        })
        |> put_resp_header("x-dawarich-handler", "phoenix-exports")
        |> put_resp_header("location", RequestURL.base(conn) <> "/exports")
        |> put_resp_header("cache-control", "no-cache")
        |> put_resp_content_type("text/html")
        |> send_resp(303, "")
        |> halt()

      {:error, :not_found} when conn.method in ["DELETE", "POST"] ->
        if Dawarich.Standalone.enabled?(),
          do: DawarichWeb.StandaloneError.respond(conn, "export_not_found", 404),
          else: DawarichWeb.Api.Body.replay(conn, "export delete not_found")

      {:error, reason} ->
        DawarichWeb.Api.Body.replay(conn, "export delete #{reason}")
    end
  end
end

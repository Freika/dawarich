defmodule DawarichWeb.UserDataController do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  alias Dawarich.Accounts.Scope
  alias Dawarich.UserData
  alias DawarichWeb.{Locale, RailsSession, RequestURL, Translate}
  @prefix "controllers.settings.users."

  def init(action), do: action

  def call(conn, :export) do
    :ok = UserData.request_export(scope(conn))

    redirect(
      conn,
      "/exports",
      "notice",
      "your_data_is_being_exported_you_will_receive_a_notification"
    )
  end

  def call(conn, :import) do
    {kind, key} =
      case UserData.start_import(scope(conn), conn.assigns.api_params["archive"]) do
        :ok -> {"notice", "your_data_import_has_been_started_you_will_receive_a"}
        {:error, :blank} -> {"alert", "please_select_a_zip_archive_to_import"}
        {:error, :validation} -> {"alert", "failed_to_start_import_please_try_again"}
        {:error, _} -> {"alert", "an_error_occurred_while_starting_the_import_please_try_again"}
      end

    redirect(conn, "/users/edit", kind, key)
  end

  defp locale(conn),
    do: Locale.resolve(nil, conn.assigns.current_user, conn.assigns.rails_session)

  defp scope(conn), do: Scope.for_user(conn.assigns.current_user, locale(conn))

  defp redirect(conn, path, kind, key) do
    message = Translate.t(locale(conn), @prefix <> key, %{})

    conn
    |> RailsSession.stage(%{"flash" => %{"discard" => [], "flashes" => %{kind => message}}})
    |> put_resp_header("location", RequestURL.base(conn) <> path)
    |> put_resp_header("x-dawarich-handler", "phoenix-user-data")
    |> put_resp_header("cache-control", "no-cache")
    |> put_resp_content_type("text/html")
    |> send_resp(302, "")
    |> halt()
  end
end

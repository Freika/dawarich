defmodule DawarichWeb.NotificationActions do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  alias Dawarich.Notifications
  alias DawarichWeb.{Locale, RailsForm, RailsSession, RequestURL, Translate}

  def init(action), do: action

  def call(conn, action) do
    expected = if action == :destroy, do: "DELETE", else: "POST"
    params = conn.assigns.api_params

    method =
      if conn.method == "POST", do: String.upcase(params["_method"] || "POST"), else: conn.method

    cond do
      is_nil(conn.assigns.current_user) ->
        conn |> put_resp_header("location", "/users/sign_in") |> send_resp(302, "") |> halt()

      method != expected ->
        conn |> send_resp(404, "") |> halt()

      RailsForm.admission(conn, allowed_overrides: ["DELETE"]) != :ok ->
        conn |> send_resp(422, "") |> halt()

      true ->
        perform(conn, action)
    end
  end

  defp perform(conn, action) do
    id = conn.assigns.current_user.id

    case action do
      :mark_as_read ->
        Notifications.mark_all_read(id)
        done(conn, "all_notifications_marked_as_read")

      :destroy_all ->
        Notifications.delete_all(id)
        done(conn, "all_notifications_where_successfully_destroyed")

      :destroy ->
        notification_id =
          DawarichWeb.Params.ruby_to_i(conn.path_params["id"] || conn.assigns.api_params["id"])

        case Notifications.get(id, notification_id) do
          nil ->
            conn |> send_resp(404, "") |> halt()

          notification ->
            Notifications.delete(id, notification.id)
            done(conn, "notification_was_successfully_destroyed")
        end
    end
  end

  defp done(conn, key) do
    locale = Locale.resolve(nil, conn.assigns.current_user, conn.assigns.rails_session)
    message = Translate.t(locale, "controllers.notifications." <> key, %{})

    conn
    |> RailsSession.stage(%{"flash" => %{"discard" => [], "flashes" => %{"notice" => message}}})
    |> put_resp_header("location", RequestURL.base(conn) <> "/notifications")
    |> put_resp_header("cache-control", "no-cache")
    |> put_resp_content_type("text/html")
    |> send_resp(303, "")
    |> halt()
  end
end

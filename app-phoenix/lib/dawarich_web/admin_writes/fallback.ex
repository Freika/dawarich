defmodule DawarichWeb.AdminWrites.Fallback do
  @moduledoc false
  import Plug.Conn
  alias DawarichWeb.{AdminWritesGate, Locale, RailsAuth, RailsProxy, StandaloneError}
  alias DawarichWeb.AdminWrites.Response

  def call(conn, opts \\ []) do
    if Dawarich.Standalone.enabled?() do
      context = AdminWritesGate.context(opts)
      conn = RailsAuth.call(conn, AdminWritesGate.auth_options(context))
      actor = conn.assigns.current_user
      action = Keyword.get(opts, :action)

      cond do
        is_nil(actor) ->
          conn |> put_resp_header("location", "/users/sign_in") |> send_resp(302, "") |> halt()

        context.self_hosted != true and action != :background ->
          refuse(conn, actor)

        action != :background and actor.admin != true ->
          refuse(conn, actor)

        true ->
          StandaloneError.respond(conn, "admin_envelope", Keyword.get(opts, :status, 422))
      end
    else
      RailsProxy.call(conn, Application.fetch_env!(:dawarich, :rails_upstream))
    end
  end

  defp refuse(conn, actor) do
    locale = Locale.resolve(nil, actor, conn.assigns.rails_session)

    {:ok, message} =
      Dawarich.I18n.t(
        locale,
        "controllers.application.you_are_not_authorized_to_perform_this_action"
      )

    Response.redirect(conn, 303, DawarichWeb.RailsRedirect.back(conn), :alert, message)
  end
end

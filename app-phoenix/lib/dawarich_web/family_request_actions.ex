defmodule DawarichWeb.FamilyRequestActions do
  @moduledoc false
  alias Dawarich.{Repo, FamilyPageAccess}
  alias Dawarich.Families.{Requests, WebCreate}
  alias DawarichWeb.FamilyActions
  def init(action), do: action

  def call(conn, action) do
    conn = FamilyActions.prepare(conn)

    if conn.halted do
      conn
    else
      user = conn.assigns.current_user
      ctx = FamilyActions.context(conn)
      family = WebCreate.family(Repo, user.id)

      cond do
        not FamilyPageAccess.available?(user, family, ctx.self_hosted, ctx.now) ->
          FamilyActions.redirect_key(
            conn,
            303,
            "/family/new",
            "alert",
            "controllers.application.family_plan_required"
          )

        is_nil(family) ->
          FamilyActions.redirect_key(
            conn,
            302,
            "/",
            "alert",
            "controllers.family.location_requests.you_must_be_part_of_a_family"
          )

        true ->
          params = Map.merge(conn.params, conn.path_params)
          user = Map.put(user, :timezone, Dawarich.UserSettings.get(user)["timezone"])

          result =
            if action == :create,
              do: Requests.web_create(user, params, ctx.now),
              else: Requests.web_respond(user, action, params, ctx.now)

          respond(conn, action, result)
      end
    end
  rescue
    _error -> FamilyActions.error(conn, :failed)
  end

  defp respond(conn, action, {:ok, status, {:object, _fields}}) when status in [200, 201] do
    key =
      case action do
        :create -> "location_request_sent_successfully"
        :accept -> "location_sharing_enabled"
        :decline -> "location_request_declined"
      end

    FamilyActions.redirect_key(
      conn,
      302,
      "/family",
      "notice",
      "controllers.family.location_requests." <> key
    )
  end

  defp respond(conn, action, {:ok, 404, _fields}) when action != :create,
    do: FamilyActions.error(conn, :not_found)

  defp respond(conn, :create, {:ok, 404, _fields}),
    do:
      FamilyActions.redirect_key(
        conn,
        302,
        "/family",
        "alert",
        "controllers.family.location_requests.user_not_found_in_your_family"
      )

  defp respond(conn, _action, {:ok, 403, _fields}),
    do:
      FamilyActions.redirect_key(
        conn,
        302,
        "/family",
        "alert",
        "controllers.family.location_requests.you_are_not_authorized_to_view_this_request"
      )

  defp respond(conn, action, {:ok, _status, {:object, fields}}),
    do:
      FamilyActions.redirect(
        conn,
        302,
        "/family",
        "alert",
        localized(conn, action, fields |> List.keyfind("message", 0) |> elem(1))
      )

  defp respond(conn, _action, _result), do: FamilyActions.error(conn, :failed)

  defp localized(conn, action, message) do
    service =
      if action == :create, do: "create_location_request", else: "respond_to_location_request"

    keys =
      if action == :create,
        do:
          ~w(target_user_is_already_sharing_their_location request_cooldown_active_please_wait_before_requesting_again an_error_occurred),
        else: ~w(no_longer_actionable an_error_occurred)

    Enum.find_value(keys, message, fn key ->
      scope = "services.families." <> service <> "." <> key

      if Dawarich.I18n.en!(scope) == message,
        do: DawarichWeb.Translate.t(conn.assigns.locale, scope, %{})
    end)
  end
end

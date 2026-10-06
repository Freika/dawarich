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
          user = Map.put(user, :timezone, user.settings["timezone"])

          result =
            if action == :create,
              do: Requests.web_create(user, params, ctx.now),
              else: Requests.respond(user, action, params, ctx.now)

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

  defp respond(conn, _action, {:ok, _status, {:object, fields}}),
    do:
      FamilyActions.redirect(
        conn,
        302,
        "/family",
        "alert",
        fields |> List.keyfind("message", 0) |> elem(1)
      )

  defp respond(conn, _action, _result), do: FamilyActions.error(conn, :failed)
end

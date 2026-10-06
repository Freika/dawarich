defmodule DawarichWeb.FamilyInvitationActions do
  @moduledoc false
  alias Dawarich.{Repo, FamilyPageAccess}
  alias Dawarich.Families.{WebInvitations, WebCreate}
  alias DawarichWeb.FamilyActions
  def init(action), do: action

  def call(conn, action) do
    conn = FamilyActions.prepare(conn)

    if conn.halted do
      conn
    else
      ctx = FamilyActions.context(conn)
      user = conn.assigns.current_user
      family = WebCreate.family(Repo, user.id)

      if action == :create and
           not FamilyPageAccess.available?(user, family, ctx.self_hosted, ctx.now) do
        FamilyActions.redirect_key(
          conn,
          303,
          "/family/new",
          "alert",
          "controllers.application.family_plan_required"
        )
      else
        result =
          case action do
            :create ->
              WebInvitations.create(Repo, user, conn.params["family_invitation"] || %{}, ctx)

            :destroy ->
              WebInvitations.cancel(Repo, user, conn.path_params["id"], ctx)

            :accept ->
              WebInvitations.accept(Repo, user, conn.params["token"], ctx)
          end

        respond(conn, action, result)
      end
    end
  rescue
    _error -> FamilyActions.error(conn, :failed)
  end

  defp respond(conn, action, {:ok, _id}) do
    key =
      case action do
        :create -> "controllers.family.invitations.invitation_sent_successfully"
        :destroy -> "controllers.family.invitations.invitation_cancelled"
        :accept -> "controllers.family.memberships.welcome_to_the_family"
      end

    FamilyActions.redirect_key(conn, 302, "/family", "notice", key)
  end

  defp respond(conn, _action, {:refused, message}),
    do: FamilyActions.redirect(conn, 302, "/family", "alert", message)

  defp respond(conn, :accept, {:error, reason}) do
    key =
      case reason do
        :invitation_expired ->
          "controllers.family.memberships.invitation_expired"

        :invitation_processed ->
          "controllers.family.memberships.invitation_processed"

        :invitation_email_mismatch ->
          "controllers.family.memberships.invitation_email_mismatch"

        :already_in_family ->
          "services.families.accept_invitation.you_must_leave_your_current_family_before_joining_a_new"

        :family_lapsed ->
          "services.families.accept_invitation.this_family_s_plan_is_no_longer_active"

        :family_full ->
          "services.families.accept_invitation.this_family_has_reached_the_maximum_number_of_members"

        _ ->
          "controllers.family.memberships.an_unexpected_error_occurred_please_try_again_later"
      end

    FamilyActions.redirect_key(conn, 302, "/", "alert", key)
  end

  defp respond(conn, _action, {:error, reason})
       when reason in [:not_in_family, :not_authorized, :not_found],
       do: FamilyActions.error(conn, reason)

  defp respond(conn, _action, {:error, :invalid_shape}), do: FamilyActions.error(conn, :failed)

  defp respond(conn, _action, {:error, _reason}),
    do:
      FamilyActions.redirect_key(
        conn,
        302,
        "/family",
        "alert",
        "controllers.family.invitations.failed_to_send_invitation"
      )
end

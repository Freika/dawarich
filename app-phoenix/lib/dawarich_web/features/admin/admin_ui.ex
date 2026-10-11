defmodule DawarichWeb.AdminUI do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3, redirect: 2]
  alias DawarichWeb.Translate

  def notice(socket, key, args \\ %{}),
    do: put_flash(socket, :notice, Translate.t(socket.assigns.locale, key, args))

  def alert(socket, key),
    do: put_flash(socket, :alert, Translate.t(socket.assigns[:locale] || "en", key, %{}))

  def refuse(socket, :stale_session), do: redirect(socket, to: "/users/sign_in")

  def refuse(socket, reason) when reason in [:unauthorized, :cloud],
    do:
      socket
      |> alert("controllers.application.you_are_not_authorized_to_perform_this_action")
      |> redirect(to: "/")

  def refuse(socket, :unsupported),
    do:
      socket
      |> alert("controllers.application.admin_action_failed")
      |> redirect(to: "/settings/general")

  def refuse(socket, :oidc),
    do: alert(socket, "controllers.application.admin_writes_unavailable_with_oidc")

  def refuse(socket, :encryption),
    do: alert(socket, "controllers.application.admin_encryption_unavailable")

  def refuse(socket, {:validation, message}), do: put_flash(socket, :alert, message)
  def refuse(socket, {:blocked, message}), do: put_flash(socket, :alert, message)

  def refuse(socket, reason) when reason in [:self, :last_admin],
    do: alert(socket, "controllers.application.you_are_not_authorized_to_perform_this_action")

  def refuse(socket, :cannot_delete_account),
    do:
      alert(
        socket,
        "controllers.settings.users.cannot_delete_account_while_being_owner_of_a_family_which"
      )

  def refuse(socket, :not_found),
    do:
      socket
      |> assign(:target, nil)
      |> alert("controllers.application.admin_action_failed")
      |> redirect(to: "/settings/users")

  def refuse(socket, _), do: alert(socket, "controllers.application.admin_action_failed")
end

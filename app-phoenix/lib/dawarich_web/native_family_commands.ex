defmodule DawarichWeb.NativeFamilyCommands do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3, push_navigate: 2]
  alias Dawarich.Families
  alias DawarichWeb.Translate

  def handle_event("family:" <> action, params, socket) do
    attrs =
      case action do
        "sharing" -> params["sharing"]
        "invite" -> params["family_invitation"]
        _ -> params
      end

    result =
      if is_map(attrs) do
        command(socket.assigns.current_scope, action, attrs,
          self_hosted: socket.assigns.self_hosted != false
        )
      else
        {:error, :invalid}
      end

    respond(socket, action, result)
  end

  defp command(scope, action, attrs, opts) do
    case action do
      "sharing" ->
        Families.set_sharing(
          scope,
          Map.take(attrs, ~w(enabled duration share_history history_window)),
          opts
        )

      "member" ->
        Families.remove_member(scope, integer(attrs["id"]), opts)

      "destroy" ->
        Families.delete(scope, opts)

      "invite" ->
        Families.invite(scope, Map.take(attrs, ["email"]), opts)

      "cancel" ->
        Families.cancel_invitation(scope, integer(attrs["id"]), opts)

      "request" ->
        Families.request_location(scope, %{"target_user_id" => attrs["id"]}, opts)

      _ ->
        {:error, :invalid_input}
    end
  end

  defp integer(value) when is_binary(value) and byte_size(value) <= 19 do
    case Integer.parse(value) do
      {id, ""} when id > 0 and id <= 9_223_372_036_854_775_807 -> id
      _ -> 0
    end
  end

  defp integer(_), do: 0

  defp respond(socket, "sharing", {:ok, config}) do
    enabled = config["enabled"]
    count = if enabled, do: Dawarich.Families.SharingUpdate.Web.hours(config["duration"]), else: 0

    key =
      cond do
        not enabled -> "disabled"
        count > 0 -> "enabled_for_hours"
        true -> "enabled"
      end

    reload(
      socket,
      "success",
      t(socket, "services.families.update_location_sharing." <> key, %{count: count})
    )
  end

  defp respond(socket, "request", {:ok, _}),
    do:
      reload(
        socket,
        "success",
        t(socket, "controllers.family.location_requests.location_request_sent_successfully")
      )

  defp respond(socket, "destroy", {:error, :members_present}),
    do: respond(socket, "destroy", {:refused, :members_present})

  defp respond(socket, "member", {:error, reason}) when is_atom(reason),
    do: respond(socket, "member", {:refused, Atom.to_string(reason)})

  defp respond(socket, "invite", {:error, %{errors: errors}}),
    do: reload(socket, "error", Enum.join(errors, ", "))

  defp respond(socket, "destroy", {:ok, _}),
    do:
      {:noreply,
       socket
       |> put_flash(:notice, t(socket, "controllers.families.family_deleted_successfully"))
       |> push_navigate(to: "/family/new")}

  defp respond(socket, "member", {:ok, %{self?: true}}),
    do:
      {:noreply,
       socket
       |> put_flash(:notice, t(socket, "controllers.family.memberships.you_have_left_the_family"))
       |> push_navigate(to: "/family/new")}

  defp respond(socket, "member", {:ok, %{email: email}}),
    do:
      reload(
        socket,
        "success",
        t(socket, "controllers.family.memberships.email_has_been_removed_from_the_family", %{
          email: email
        })
      )

  defp respond(socket, "request", {:ok, status, _}) when status in [200, 201],
    do:
      reload(
        socket,
        "success",
        t(socket, "controllers.family.location_requests.location_request_sent_successfully")
      )

  defp respond(socket, _, {:ok, status, {:object, fields}}),
    do:
      reload(
        socket,
        if(status < 300, do: "success", else: "error"),
        fields |> Map.new() |> then(&(&1["message"] || &1["error"] || ""))
      )

  defp respond(socket, "invite", {:ok, _}),
    do:
      reload(
        socket,
        "success",
        t(socket, "controllers.family.invitations.invitation_sent_successfully")
      )

  defp respond(socket, "cancel", {:ok, _}),
    do:
      reload(socket, "success", t(socket, "controllers.family.invitations.invitation_cancelled"))

  defp respond(socket, "destroy", {:refused, :members_present}),
    do:
      reload(
        socket,
        "error",
        t(
          socket,
          "controllers.families.cannot_delete_family_with_members_remove_all_members_first"
        )
      )

  defp respond(socket, "member", {:refused, reason}),
    do: reload(socket, "error", t(socket, "services.families.memberships.destroy." <> reason))

  defp respond(socket, "invite", {:refused, message}), do: reload(socket, "error", message)

  defp respond(socket, _, _),
    do:
      reload(
        socket,
        "error",
        t(
          socket,
          "controllers.family.memberships.an_unexpected_error_occurred_please_try_again_later"
        )
      )

  defp reload(socket, kind, message) do
    {_, socket} = DawarichWeb.NativeFamilyResource.admit(socket)

    socket =
      if socket.assigns.current_scope do
        navbar =
          Dawarich.Maps.with_actor(socket.assigns.current_scope, fn actor ->
            Dawarich.Navbar.load(actor,
              now: socket.assigns.now,
              self_hosted: socket.assigns.self_hosted != false
            )
          end)

        assign(socket, :navbar, navbar)
      else
        socket
      end

    {:noreply, put_flash(socket, kind, message)}
  end

  defp t(socket, key, bindings \\ %{}), do: Translate.t(socket.assigns.locale, key, bindings)
end

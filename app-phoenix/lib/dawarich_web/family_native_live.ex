defmodule DawarichWeb.FamilyNativeLive do
  @moduledoc false
  import Phoenix.Component, only: [assign: 2, assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3, push_event: 3, push_navigate: 2]
  alias Dawarich.Families
  alias DawarichWeb.NativeFamilyAuth

  def mount(socket) do
    page = socket.assigns.page

    assign(socket,
      errors: [],
      confirmation: nil,
      family_name: get_in(page, [:family, :name]) || "",
      invitation_email: "",
      page_title: get_in(page, [:family, :name]),
      rails_js: false
    )
  end

  def event("family_save", %{"family" => attrs}, socket) when is_map(attrs) do
    name = attrs["name"]

    socket =
      assign(
        socket,
        :family_name,
        if(is_binary(name) and byte_size(name) <= 4096, do: name, else: "")
      )

    action = if socket.assigns.page.state == :edit, do: :update, else: :create

    case apply(Families, action, [socket.assigns.current_scope, attrs, opts(socket)]) do
      {:ok, _} ->
        {:noreply,
         socket
         |> notice(
           "controllers.families.family_#{if(action == :create, do: "created", else: "updated")}_successfully"
         )
         |> push_navigate(to: "/family")}

      error ->
        {:noreply, error(socket, error)}
    end
  end

  def event("family_invite", %{"family_invitation" => attrs}, socket) when is_map(attrs) do
    email = attrs["email"]

    socket =
      assign(
        socket,
        :invitation_email,
        if(is_binary(email) and byte_size(email) <= 512, do: email, else: "")
      )

    case Families.invite(socket.assigns.current_scope, attrs, opts(socket)) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(invitation_email: "", errors: [])
         |> notice("controllers.family.invitations.invitation_sent_successfully")
         |> refresh()}

      reason ->
        {:noreply, error(socket, reason)}
    end
  end

  def event("family_set_sharing", attrs, socket) when is_map(attrs) do
    case Families.set_sharing(
           socket.assigns.current_scope,
           Map.take(
             attrs,
             ~w(enabled duration share_history history_window history_before_sharing)
           ),
           opts(socket)
         ) do
      {:ok, config} ->
        hours =
          if config["enabled"],
            do: Dawarich.Families.SharingUpdate.Web.hours(attrs["duration"]),
            else: 0

        key =
          cond do
            config["enabled"] != true -> "disabled"
            hours > 0 -> "enabled_for_hours"
            true -> "enabled"
          end

        {:noreply,
         socket
         |> assign(:errors, [])
         |> notice("services.families.update_location_sharing." <> key, %{count: hours})
         |> refresh()}

      reason ->
        {:noreply, error(socket, reason)}
    end
  end

  def event("family_request_location", attrs, socket) when is_map(attrs) do
    case Families.request_location(socket.assigns.current_scope, attrs, opts(socket)) do
      {:ok, _} ->
        {:noreply,
         socket
         |> notice("controllers.family.location_requests.location_request_sent_successfully")
         |> refresh()}

      reason ->
        {:noreply, error(socket, reason)}
    end
  end

  def event("family_respond", attrs, %{assigns: %{family_action: {:request, id}}} = socket)
      when is_map(attrs) do
    decision =
      case attrs["decision"] do
        "accept" -> :accept
        "decline" -> :decline
        _ -> nil
      end

    if decision do
      case Families.respond_location(
             socket.assigns.current_scope,
             id,
             decision,
             Map.take(attrs, ["duration"]),
             opts(socket)
           ) do
        {:ok, _} -> {:noreply, socket |> assign(:errors, []) |> refresh()}
        reason -> {:noreply, error(socket, reason)}
      end
    else
      {:noreply, error(socket, {:error, :invalid_input})}
    end
  end

  def event("family_prepare_confirm", attrs, socket) when is_map(attrs) do
    action = attrs["action"]
    id = id(attrs["id"])
    page = socket.assigns.page
    me = page[:me] || %{}

    allowed =
      case action do
        "delete" ->
          page[:owner?] == true

        "remove_member" ->
          id != nil and Enum.any?(page[:members] || [], &(&1.membership_id == id)) and
            (page[:owner?] == true or id == me[:membership_id])

        "cancel_invitation" ->
          page[:owner?] == true and Enum.any?(page[:invitations] || [], &(&1.id == id))

        _ ->
          false
      end

    if allowed,
      do: {:noreply, assign(socket, confirmation: %{action: action, id: id}, errors: [])},
      else: {:noreply, error(socket, {:error, :unauthorized})}
  end

  def event("family_cancel_confirm", _, socket),
    do: {:noreply, assign(socket, :confirmation, nil)}

  def event("family_confirm", _, %{assigns: %{confirmation: nil}} = socket),
    do: {:noreply, socket}

  def event("family_confirm", _, socket) do
    pending = socket.assigns.confirmation
    socket = assign(socket, :confirmation, nil)

    result =
      case pending.action do
        "delete" ->
          Families.delete(socket.assigns.current_scope, opts(socket))

        "remove_member" ->
          Families.remove_member(socket.assigns.current_scope, pending.id, opts(socket))

        "cancel_invitation" ->
          Families.cancel_invitation(socket.assigns.current_scope, pending.id, opts(socket))
      end

    socket = push_event(socket, "close-dialog", %{id: "family-confirm"})

    case result do
      {:ok, %{self?: true}} ->
        {:noreply,
         socket
         |> notice("controllers.family.memberships.you_have_left_the_family")
         |> push_navigate(to: "/family/new")}

      {:ok, %{email: email}} ->
        {:noreply,
         socket
         |> notice("controllers.family.memberships.email_has_been_removed_from_the_family", %{
           email: email
         })
         |> refresh()}

      {:ok, _} when pending.action == "delete" ->
        {:noreply,
         socket
         |> notice("controllers.families.family_deleted_successfully")
         |> push_navigate(to: "/family/new")}

      {:ok, _} ->
        {:noreply,
         socket |> notice("controllers.family.invitations.invitation_cancelled") |> refresh()}

      reason ->
        {:noreply, error(socket, reason)}
    end
  end

  def event(_, _, socket), do: {:noreply, socket}

  def refresh(socket) do
    case NativeFamilyAuth.authorize(socket) do
      {:cont, socket} -> DawarichWeb.FamilyDelivery.reload(socket)
      {_, socket} -> socket
    end
  end

  def opts(socket), do: [now: socket.assigns.now, self_hosted: socket.assigns.self_hosted]

  defp notice(socket, key, bindings \\ %{}),
    do: put_flash(socket, :notice, DawarichWeb.Translate.t(socket.assigns.locale, key, bindings))

  defp error(socket, {:error, %{errors: errors}}),
    do: assign(socket, :errors, Enum.map(errors, &message/1))

  defp error(socket, {:error, reason}) do
    key =
      case reason do
        :members_present ->
          "controllers.families.cannot_delete_family_with_members_remove_all_members_first"

        :expired ->
          "controllers.application.family_plan_required"

        :unauthorized ->
          "controllers.application.you_are_not_authorized_to_perform_this_action"

        _ ->
          "javascript.common.unknown_error"
      end

    assign(socket, :errors, [DawarichWeb.Translate.t(socket.assigns.locale, key, %{})])
  end

  defp error(socket, _), do: error(socket, {:error, :unavailable})
  defp message({_, text}) when is_binary(text), do: text
  defp message(text) when is_binary(text), do: text
  defp message(_), do: ""

  defp id(id) when is_binary(id) and byte_size(id) <= 19 do
    case Integer.parse(id) do
      {id, ""} when id > 0 and id <= 9_223_372_036_854_775_807 -> id
      _ -> nil
    end
  end

  defp id(_), do: nil
end

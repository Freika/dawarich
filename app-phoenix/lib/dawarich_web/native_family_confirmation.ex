defmodule DawarichWeb.NativeFamilyConfirmation do
  @moduledoc false
  import Phoenix.Component, only: [assign: 2, assign: 3]
  import Phoenix.LiveView, only: [push_event: 3]

  def handle_event("family_prepare_confirm", params, socket) do
    page = socket.assigns.page

    {:noreply, prepared} =
      socket
      |> assign(:page, page.presentation)
      |> then(&DawarichWeb.FamilyNativeLive.event("family_prepare_confirm", params, &1))

    {:noreply, assign(prepared, :page, page)}
  end

  def handle_event("family_cancel_confirm", _, socket),
    do: {:noreply, assign(socket, :confirmation, nil)}

  def handle_event("family_confirm", _, %{assigns: %{confirmation: nil}} = socket),
    do: {:noreply, socket}

  def handle_event("family_confirm", _, socket) do
    pending = socket.assigns.confirmation

    action =
      case pending.action do
        "delete" -> "destroy"
        "remove_member" -> "member"
        "cancel_invitation" -> "cancel"
      end

    socket =
      socket
      |> assign(confirmation: nil, errors: [])
      |> push_event("close-dialog", %{id: "family-confirm"})

    DawarichWeb.NativeFamilyCommands.handle_event(
      "family:" <> action,
      %{"id" => to_string(pending.id)},
      socket
    )
  end
end

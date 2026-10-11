defmodule DawarichWeb.FamiliesLive.NativeMap do
  @moduledoc false
  use DawarichWeb, :live_view
  on_mount {DawarichWeb.MapLiveAuth, :default}

  def mount(_, _, %{assigns: %{current_scope: nil}} = socket), do: {:ok, socket, layout: false}

  def mount(_, _, socket),
    do:
      {:ok,
       socket
       |> assign(confirmation: nil, errors: [])
       |> DawarichWeb.NativeFamilyResource.attach()
       |> maybe_chrome(), layout: false}

  def handle_params(_, _, %{assigns: %{current_scope: nil}} = socket), do: {:noreply, socket}

  def handle_params(_, _, socket) do
    {_, socket} = DawarichWeb.NativeFamilyResource.admit(socket)

    if socket.assigns.current_scope do
      {:noreply,
       DawarichWeb.MapLive.Subscriptions.sync(socket, %{
         kind: :family,
         scope: socket.assigns.current_scope
       })}
    else
      {:noreply, socket}
    end
  end

  def handle_event("family:" <> _ = event, params, socket),
    do: DawarichWeb.NativeFamilyCommands.handle_event(event, params, socket)

  def handle_event(event, params, socket)
      when event in ~w(family_prepare_confirm family_cancel_confirm family_confirm),
      do: DawarichWeb.NativeFamilyConfirmation.handle_event(event, params, socket)

  def handle_event(_, _, socket), do: {:noreply, socket}

  def handle_info(message, socket) do
    case DawarichWeb.MapLive.Subscriptions.deliver(socket, message) do
      {:refused, s} -> {:noreply, DawarichWeb.NativeFamilyResource.refuse(s, :not_found)}
      {_, s} -> {:noreply, s}
    end
  end

  def terminate(_, socket), do: DawarichWeb.NativeFamilyConsent.cancel(socket)

  defp maybe_chrome(%{assigns: %{current_scope: nil}} = socket), do: socket
  defp maybe_chrome(socket), do: DawarichWeb.NativeMapChrome.load(socket)
  def render(assigns), do: DawarichWeb.NativeFamilyPage.page(assigns)
end

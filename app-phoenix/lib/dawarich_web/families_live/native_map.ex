defmodule DawarichWeb.FamiliesLive.NativeMap do
  @moduledoc false
  use DawarichWeb, :live_view
  on_mount {DawarichWeb.MapLiveAuth, :default}

  def mount(_, _, %{assigns: %{current_scope: nil}} = socket), do: {:ok, socket, layout: false}

  def mount(_, _, socket),
    do:
      {:ok, socket |> DawarichWeb.NativeFamilyResource.attach() |> maybe_chrome(), layout: false}

  def handle_event(_, _, socket), do: {:noreply, socket}

  def handle_info(message, socket) do
    case DawarichWeb.MapLive.Subscriptions.deliver(socket, message) do
      {:refused, s} -> {:noreply, DawarichWeb.NativeFamilyResource.refuse(s, :not_found)}
      {_, s} -> {:noreply, s}
    end
  end

  defp maybe_chrome(%{assigns: %{current_scope: nil}} = socket), do: socket
  defp maybe_chrome(socket), do: DawarichWeb.NativeMapChrome.load(socket)
  def render(assigns), do: DawarichWeb.NativeFamilyPage.page(assigns)
end

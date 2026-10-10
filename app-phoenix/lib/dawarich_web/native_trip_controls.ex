defmodule DawarichWeb.NativeTripControls do
  @moduledoc false
  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [push_event: 3]
  alias DawarichWeb.NativeTripState

  def handle_event(event, params, socket) do
    case NativeTripState.refresh(socket) do
      {:ok, socket} -> {:noreply, command(event, params, socket)}
      {:error, socket} -> {:noreply, socket}
    end
  end

  defp command("trip:days:all", _, socket) do
    socket
    |> assign(expanded_days: !socket.assigns.expanded_days, selected_day: nil)
    |> push_event("trip:select_day", %{day: nil})
  end

  defp command("trip:layer", %{"layer" => layer}, socket) do
    key = NativeTripState.layer_key(socket.assigns.page.presentation, layer)

    socket =
      if key do
        enabled = !socket.assigns.page.config[key]
        page = put_in(socket.assigns.page, [:config, key], enabled)
        choices = Map.put(socket.assigns.trip_layers, key, enabled)
        assign(socket, page: page, trip_layers: choices)
      else
        socket
      end

    push_event(socket, "map:config", socket.assigns.page.config)
  end

  defp command(_, _, socket), do: socket
end

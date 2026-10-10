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

  defp command("trip:plan:focus", %{"id" => id}, socket) when is_binary(id) or is_integer(id) do
    stop =
      socket.assigns.page.presentation.plan.days
      |> Enum.flat_map(& &1.stops)
      |> Enum.find(&(to_string(&1.id) == to_string(id)))

    if socket.assigns.page.config["planEnabled"] && stop do
      longitude = coordinate(stop.longitude)
      latitude = coordinate(stop.latitude)

      if is_number(longitude) and longitude >= -180 and longitude <= 180 and
           is_number(latitude) and latitude >= -90 and latitude <= 90 do
        push_event(socket, "trip:focus", %{longitude: longitude, latitude: latitude})
      else
        socket
      end
    else
      socket
    end
  end

  defp command(_, _, socket), do: socket

  defp coordinate(%Decimal{} = value), do: Decimal.to_float(value)
  defp coordinate(value) when is_number(value), do: value
  defp coordinate(_), do: nil
end

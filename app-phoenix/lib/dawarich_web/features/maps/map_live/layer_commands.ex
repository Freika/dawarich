defmodule DawarichWeb.MapLive.LayerCommands do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3]

  def handle_event("map:visits_filter", %{"query" => query, "status" => status}, socket)
      when is_binary(query) and status in ~w(all confirmed suggested) do
    config =
      Map.put(socket.assigns.map_config, "visitFilter", %{
        "query" => String.slice(query, 0, 100),
        "status" => status
      })

    {:noreply, socket |> assign(:map_config, config) |> push_event("map:config", config)}
  end

  def handle_event("map:flights", %{"enabled" => value}, socket)
      when value in [true, false, "true", "false"] do
    enabled = value in [true, "true"]

    config =
      socket.assigns.map_config
      |> Map.put("flightsPreferred", enabled)
      |> Map.put("flightsEnabled", enabled and socket.assigns.map_config["airtrailConfigured"])

    {:noreply, socket |> assign(:map_config, config) |> push_event("map:config", config)}
  end

  def handle_event("map:flights", params, socket) when not is_map_key(params, "enabled") do
    enabled = Map.get(socket.assigns.map_config, "flightsPreferred", true) != true
    handle_event("map:flights", %{"enabled" => enabled}, socket)
  end

  def handle_event("map:anomalies", %{"enabled" => value}, socket)
      when value in ["true", "false"] do
    config =
      socket.assigns.map_config
      |> Map.put("anomaliesPreferred", value == "true")
      |> Map.put(
        "anomaliesEnabled",
        value == "true" and socket.assigns.map_config["pointsEnabled"]
      )

    {:noreply, socket |> assign(:map_config, config) |> push_event("map:config", config)}
  end

  def handle_event("map:anomalies", params, socket) when not is_map_key(params, "enabled"),
    do: handle_event("map:anomalies", %{"enabled" => flip(socket, "anomaliesPreferred")}, socket)

  def handle_event(_, _, socket), do: {:noreply, socket}

  defp flip(socket, key), do: to_string(socket.assigns.map_config[key] != true)
end

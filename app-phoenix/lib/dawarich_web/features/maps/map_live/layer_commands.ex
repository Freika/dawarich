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

  def handle_event("map:flights", %{"enabled" => value}, socket) when value in ~w(true false) do
    config =
      socket.assigns.map_config
      |> Map.put("flightsPreferred", value == "true")
      |> Map.put(
        "flightsEnabled",
        value == "true" and socket.assigns.map_config["airtrailConfigured"]
      )

    {:noreply, socket |> assign(:map_config, config) |> push_event("map:config", config)}
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

  def handle_event(_, _, socket), do: {:noreply, socket}
end

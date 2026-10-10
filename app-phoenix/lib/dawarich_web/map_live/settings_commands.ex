defmodule DawarichWeb.MapLive.SettingsCommands do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3]
  alias Dawarich.Settings.Map, as: MapSettings

  @appearance ~w(maps_maplibre_style maps_maplibre_tiles_url maps_maplibre_tiles_fallback globe_projection distance_unit)

  def load(socket) do
    case MapSettings.get(socket.assigns.current_scope) do
      {:ok, settings} ->
        assign(socket, :map_settings, %{saved: settings, draft_modes: nil, error: nil})

      _ ->
        assign(socket, :map_settings, nil)
    end
  end

  def handle_event("settings:transport_change", params, socket),
    do: {:noreply, update(socket, &%{&1 | draft_modes: modes(params), error: nil})}

  def handle_event("settings:transport_apply", params, socket),
    do: save(socket, %{"enabled_transportation_modes" => modes(params)})

  def handle_event("settings:appearance", params, socket),
    do:
      save(
        socket,
        for(key <- @appearance, is_binary(params[key]), into: %{}, do: {key, params[key]})
      )

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp save(socket, attrs) do
    case MapSettings.update(socket.assigns.current_scope, attrs) do
      {:ok, %{settings: settings, recalculation_triggered: triggered}} ->
        {:noreply,
         socket
         |> assign(:map_settings, %{saved: settings, draft_modes: nil, error: nil})
         |> push_event("map:settings", %{settings: settings, recalculation_triggered: triggered})}

      {:error, {:invalid, errors}} ->
        {:noreply, update(socket, &%{&1 | error: Enum.join(errors, ", ")})}

      {:error, reason} ->
        {:noreply, update(socket, &%{&1 | error: reason})}
    end
  end

  defp update(socket, fun) do
    case socket.assigns[:map_settings] do
      nil -> socket
      settings -> assign(socket, :map_settings, fun.(settings))
    end
  end

  defp modes(%{"modes" => modes}) when is_list(modes), do: Enum.filter(modes, &is_binary/1)
  defp modes(_), do: []
end

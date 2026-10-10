defmodule DawarichWeb.MapLive.SettingsCommands do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3]
  alias Dawarich.Settings.Map, as: MapSettings
  alias Dawarich.Settings.MapForm

  def load(socket) do
    scope = socket.assigns.current_scope

    case MapSettings.get(scope) do
      {:ok, settings} ->
        assign(socket, :map_settings, %{
          saved: settings,
          draft_modes: nil,
          error: nil,
          notice: nil,
          restricted: MapSettings.restricted?(scope) != {:ok, false},
          themes: Dawarich.MapPage.poster_themes()
        })

      _ ->
        assign(socket, :map_settings, nil)
    end
  end

  def handle_event("settings:transport_change", params, socket),
    do: {:noreply, update(socket, &%{&1 | draft_modes: modes(params), error: nil})}

  def handle_event("settings:transport_apply", params, socket),
    do: save(socket, %{"enabled_transportation_modes" => modes(params)})

  def handle_event("settings:appearance", params, socket),
    do: save(socket, MapForm.appearance(params))

  def handle_event("settings:layers", params, socket),
    do: save(socket, MapForm.layers(params))

  def handle_event("settings:advanced", params, socket),
    do: save(socket, MapForm.advanced(params))

  def handle_event("settings:track_color_reset", _params, socket),
    do: save(socket, %{"track_color" => MapForm.defaults()["track_color"]})

  def handle_event("settings:reset", _params, socket),
    do: save(socket, MapForm.defaults())

  def handle_event("settings:theme_preset", %{"key" => key}, socket) do
    case MapForm.preset(key) do
      {:ok, theme} ->
        save(socket, %{"maps_maplibre_style" => "custom", "maps_maplibre_custom_theme" => theme})

      {:error, reason} ->
        {:noreply, update(socket, &%{&1 | error: reason, notice: nil})}
    end
  end

  def handle_event("settings:theme", %{"tokens" => tokens}, socket) when is_map(tokens) do
    base =
      case socket.assigns[:map_settings] do
        %{saved: %{"maps_maplibre_custom_theme" => %{"base" => base}}} when is_binary(base) ->
          base

        _ ->
          "noir"
      end

    save(socket, MapForm.theme(base, tokens))
  end

  def handle_event("settings:recalculate", _params, socket),
    do: queue(socket, MapSettings.recalculate(socket.assigns.current_scope), :recalculation)

  def handle_event("settings:reapply_anomalies", _params, socket),
    do: queue(socket, MapSettings.reapply_anomalies(socket.assigns.current_scope), :anomalies)

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp queue(socket, :ok, kind),
    do: {:noreply, update(socket, &%{&1 | notice: kind, error: nil})}

  defp queue(socket, {:error, reason}, kind),
    do: {:noreply, update(socket, &%{&1 | error: {kind, reason}, notice: nil})}

  defp save(socket, attrs) when map_size(attrs) == 0, do: {:noreply, socket}

  defp save(socket, attrs) do
    case MapSettings.update(socket.assigns.current_scope, attrs) do
      {:ok, %{settings: settings, recalculation_triggered: triggered}} ->
        {:noreply,
         socket
         |> update(&%{&1 | saved: settings, draft_modes: nil, error: nil, notice: nil})
         |> push_event("map:settings", %{settings: settings, recalculation_triggered: triggered})}

      {:error, {:invalid, errors}} ->
        {:noreply, update(socket, &%{&1 | error: Enum.join(errors, ", "), notice: nil})}

      {:error, reason} ->
        {:noreply, update(socket, &%{&1 | error: reason, notice: nil})}
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

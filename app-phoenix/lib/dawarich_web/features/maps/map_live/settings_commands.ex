defmodule DawarichWeb.MapLive.SettingsCommands do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3]
  alias Dawarich.Settings.Map, as: MapSettings
  alias Dawarich.Settings.MapForm
  alias DawarichWeb.MapLive.{Toast, SettingsToast}

  def load(socket) do
    scope = socket.assigns.current_scope

    case MapSettings.get(scope) do
      {:ok, settings} ->
        assign(socket, :map_settings, %{
          saved: settings,
          draft_modes: nil,
          dirty: %{},
          draft: %{},
          error: nil,
          notice: nil,
          restricted: MapSettings.restricted?(scope) != {:ok, false},
          themes: Dawarich.MapPage.poster_themes()
        })

      _ ->
        assign(socket, :map_settings, nil)
    end
  end

  def handle_event("settings:point_edit", %{"enabled" => value}, socket)
      when value in [true, false, "true", "false"] do
    enabled = value in [true, "true"]
    layers = socket.assigns.map_settings.saved["enabled_map_layers"] || []
    layers = if enabled, do: Enum.uniq(layers ++ ["Points"]), else: layers
    save(socket, %{"point_dragging_enabled" => enabled, "enabled_map_layers" => layers})
  end

  def handle_event("settings:point_edit", _params, socket) do
    enabled = socket.assigns.map_settings.saved["point_dragging_enabled"] != true
    handle_event("settings:point_edit", %{"enabled" => enabled}, socket)
  end

  def handle_event("settings:place_tags_all", _params, socket) do
    choices = ["untagged" | Enum.map(socket.assigns.page.tags, & &1.id)]
    filters = socket.assigns.map_settings.saved["places_tag_filters"]
    all? = is_nil(filters) or Enum.sort(filters) == Enum.sort(choices)
    save(socket, %{"places_tag_filters" => if(all?, do: [], else: choices)})
  end

  def handle_event("settings:place_tags", params, socket) do
    allowed =
      Map.new(socket.assigns.page.tags, &{to_string(&1.id), &1.id})
      |> Map.put("untagged", "untagged")

    filters =
      List.wrap(params["place_tag_ids"])
      |> Enum.filter(&Map.has_key?(allowed, &1))
      |> Enum.map(&allowed[&1])
      |> Enum.uniq()

    save(socket, %{"places_tag_filters" => filters})
  end

  def handle_event("settings:family_layer", params, socket) do
    layers = socket.assigns.map_settings.saved["enabled_map_layers"] || []

    if socket.assigns.page.family do
      layers =
        if params["enabled"] == "true",
          do: Enum.uniq(layers ++ ["Family Members"]),
          else: List.delete(layers, "Family Members")

      save(socket, %{"enabled_map_layers" => layers})
    else
      {:noreply, socket}
    end
  end

  def handle_event("settings:layer", %{"layer" => layer}, socket) do
    layers = socket.assigns.map_settings.saved["enabled_map_layers"] || []

    if layer in DawarichWeb.NativeMapPanels.layers() and layer != "Family Members" do
      layers =
        if layer in layers, do: List.delete(layers, layer), else: layers ++ [layer]

      save(socket, %{"enabled_map_layers" => layers})
    else
      {:noreply, socket}
    end
  end

  def handle_event("settings:fog_mode", %{"mode" => mode}, socket)
      when mode in ["points", "hexagons"],
      do: save(socket, %{"fog_of_war_mode" => mode})

  def handle_event("settings:place_tag", %{"tag" => tag}, socket) do
    choices = ["untagged" | Enum.map(socket.assigns.page.tags, & &1.id)]
    chosen = Enum.find(choices, &(to_string(&1) == tag))
    current = socket.assigns.map_settings.saved["places_tag_filters"] || choices

    if chosen do
      filters =
        if chosen in current,
          do: List.delete(current, chosen),
          else: Enum.filter(choices, &(&1 in current or &1 == chosen))

      save(socket, %{"places_tag_filters" => filters})
    else
      {:noreply, socket}
    end
  end

  def handle_event("settings:map_layers", params, socket) do
    layers =
      List.wrap(params["layers"])
      |> Enum.filter(&(&1 in DawarichWeb.NativeMapPanels.layers() and &1 != "Family Members"))
      |> Enum.uniq()

    family = "Family Members" in socket.assigns.map_settings.saved["enabled_map_layers"]
    layers = if family, do: layers ++ ["Family Members"], else: layers
    attrs = %{"enabled_map_layers" => layers}

    attrs =
      if params["fog_mode"] in ~w(points hexagons),
        do: Map.put(attrs, "fog_of_war_mode", params["fog_mode"]),
        else: attrs

    save(socket, attrs)
  end

  def handle_event("settings:form", %{"_target" => target} = params, socket) do
    alias DawarichWeb.MapLive.SettingsForm
    saved = socket.assigns.map_settings.saved

    socket =
      update(socket, fn settings ->
        %{
          settings
          | draft_modes: SettingsForm.modes(params),
            draft: SettingsForm.draft(params),
            dirty: SettingsForm.dirty(params, saved, socket.assigns[:locale] || "en")
        }
      end)

    case SettingsForm.immediate(target, params, saved) do
      nil -> {:noreply, socket}
      attrs -> save(socket, attrs)
    end
  end

  def handle_event("settings:apply", params, socket) do
    socket = update(socket, &%{&1 | dirty: %{}, draft: %{}})

    save(
      socket,
      DawarichWeb.MapLive.SettingsForm.advanced(params),
      "messages.settings_updated_successfully"
    )
  end

  def handle_event("settings:tile_category", %{"category" => key}, socket),
    do: toggle_list(socket, "hidden_tile_categories", MapForm.tile_categories(), key)

  def handle_event("settings:poi_group", %{"group" => key}, socket),
    do: toggle_list(socket, "disabled_poi_groups", MapForm.poi_groups(), key)

  def handle_event("settings:live", _params, socket),
    do:
      save(socket, %{
        "live_map_enabled" => socket.assigns.map_settings.saved["live_map_enabled"] == false
      })

  def handle_event("settings:reclassify", _params, socket) do
    create =
      &Dawarich.Tracks.WebRecalculation.create(Dawarich.Repo, &1, %{now: DateTime.utc_now()})

    case Dawarich.Maps.with_actor(socket.assigns.current_scope, create) do
      {:ok, _} -> {:noreply, update(socket, &%{&1 | notice: :reclassify, error: nil})}
      _ -> {:noreply, update(socket, &%{&1 | error: :reclassify, notice: nil})}
    end
  end

  def handle_event("settings:transport_apply", _params, socket),
    do:
      save(socket, %{
        "enabled_transportation_modes" =>
          socket.assigns.map_settings.draft_modes ||
            socket.assigns.map_settings.saved["enabled_transportation_modes"]
      })

  def handle_event("settings:track_color_reset", _params, socket),
    do: save(socket, %{"track_color" => MapForm.defaults()["track_color"]})

  def handle_event("settings:reset", _params, socket),
    do: socket |> update(&%{&1 | dirty: %{}, draft: %{}}) |> save(MapForm.defaults())

  def handle_event("settings:theme_preset", %{"key" => key}, socket) do
    case MapForm.preset(key) do
      {:ok, theme} ->
        save(socket, %{"maps_maplibre_style" => "custom", "maps_maplibre_custom_theme" => theme})

      {:error, _reason} ->
        {:noreply,
         socket
         |> update(&%{&1 | error: nil, notice: nil})
         |> Toast.push(:error, "messages.failed_to_update_settings")}
    end
  end

  def handle_event("settings:recalculate", _params, socket),
    do: queue(socket, MapSettings.recalculate(socket.assigns.current_scope), :recalculation)

  def handle_event("settings:reapply_anomalies", _params, socket),
    do: queue(socket, MapSettings.reapply_anomalies(socket.assigns.current_scope), :anomalies)

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp queue(socket, result, kind),
    do:
      {:noreply,
       socket |> update(&%{&1 | notice: nil, error: nil}) |> SettingsToast.queue(result, kind)}

  defp save(socket, attrs, success_key \\ nil)
  defp save(socket, attrs, _success_key) when map_size(attrs) == 0, do: {:noreply, socket}

  defp save(socket, attrs, success_key) do
    case MapSettings.update(socket.assigns.current_scope, attrs) do
      {:ok, %{settings: settings, recalculation_triggered: triggered}} ->
        {:noreply,
         socket
         |> update(
           &%{
             &1
             | saved: settings,
               draft_modes:
                 if(Map.has_key?(attrs, "enabled_transportation_modes"),
                   do: nil,
                   else: &1.draft_modes
                 ),
               error: nil,
               notice: nil
           }
         )
         |> SettingsToast.saved(attrs, settings, triggered)
         |> SettingsToast.success(success_key)
         |> push_event("map:settings", %{settings: settings, recalculation_triggered: triggered})}

      {:error, {:invalid, _errors}} ->
        {:noreply,
         socket |> update(&%{&1 | error: nil, notice: nil}) |> SettingsToast.invalid(attrs)}

      {:error, reason} ->
        {:noreply,
         socket |> update(&%{&1 | error: nil, notice: nil}) |> SettingsToast.failed(reason)}
    end
  end

  defp update(socket, fun) do
    case socket.assigns[:map_settings] do
      nil -> socket
      settings -> assign(socket, :map_settings, fun.(settings))
    end
  end

  defp toggle_list(socket, key, choices, item) do
    maps = socket.assigns.map_settings.saved["maps"] || %{}
    hidden = maps[key] || []

    if item in choices do
      hidden = if item in hidden, do: List.delete(hidden, item), else: hidden ++ [item]

      save(socket, %{"maps" => Map.put(maps, key, hidden)})
    else
      {:noreply, socket}
    end
  end
end

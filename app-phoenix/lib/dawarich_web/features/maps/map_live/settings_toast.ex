defmodule DawarichWeb.MapLive.SettingsToast do
  @moduledoc false
  alias DawarichWeb.MapLive.Toast

  def success(socket, nil), do: socket
  def success(socket, key), do: Toast.push(socket, :success, key)

  def queue(socket, :ok, kind),
    do:
      Toast.push(
        socket,
        :success,
        if(kind == :anomalies,
          do: "settings.re_evaluation_queued",
          else: "settings.recalculation_queued"
        )
      )

  def queue(socket, {:error, _}, kind),
    do:
      Toast.push(
        socket,
        :error,
        if(kind == :anomalies,
          do: "messages.could_not_queue_re_evaluation_please_try_again",
          else: "messages.could_not_queue_recalculation_please_try_again"
        )
      )

  def saved(socket, attrs, settings, triggered) do
    cond do
      Map.has_key?(attrs, "live_map_enabled") ->
        Toast.push(
          socket,
          :info,
          "live_map." <>
            if(settings["live_map_enabled"] != false, do: "enabled", else: "disabled")
        )

      Map.has_key?(attrs, "globe_projection") ->
        Toast.push(socket, :info, "messages.globe_view_will_be_applied_after_page_reload")

      triggered ->
        Toast.push(socket, :info, "settings.transportation_recalculation_started")

      Map.has_key?(attrs, "enabled_transportation_modes") ->
        Toast.push(socket, :success, "messages.transportation_settings_saved")

      true ->
        socket
    end
  end

  def invalid(socket, attrs),
    do:
      Toast.push(
        socket,
        :error,
        if(Map.has_key?(attrs, "maps_maplibre_tiles_url"),
          do: "settings.invalid_tile_url",
          else: "messages.failed_to_update_settings"
        )
      )

  def failed(socket, reason),
    do:
      Toast.push(
        socket,
        :error,
        if(reason == :locked,
          do: "messages.cannot_update_recalculation_is_already_in_progress",
          else: "messages.failed_to_update_settings"
        )
      )
end

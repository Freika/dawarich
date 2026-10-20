defmodule DawarichWeb.NativeMapLabels do
  @moduledoc false
  @keys ~w(messages.retry messages.failed_to_load_map_tiles messages.failed_to_load_visited_countries common.confirm common.delete common.close common.not_available visits.selected visits.merge visits.none_found visits.none_found_for selection.points selection.visits selection.confirm_delete_points selection.delete_anomaly_points selection.confirm_delete_anomaly_points selection.delete_points_failed messages.failed_to_confirm_visits messages.failed_to_delete_visit messages.failed_to_merge_visits messages.point_label messages.edit_history messages.edit_history_capacity messages.undo messages.redo messages.redo_to_here messages.undo_to_here messages.point_edit_conflict messages.failed_to_update_point_position_please_try_again replay.no_data_loaded replay.no_data_at_this_time replay.speed replay.day_count replay.point_count search.unnamed_location search.searching_for_visits search.locations_found search.visits_load_failed map_info.location_coordinates map_info.overlapping_points selection.delete_points selection.visits_in_area visits.unnamed map_info.duration_hours_minutes map_info.duration_minutes visit_statuses.confirmed visit_statuses.declined visit_statuses.suggested search.searching search.no_locations search.suggestions_failed search.unknown_location search.first_last search.for_query map_info.location_point map_info.coordinates map_info.time map_info.battery map_info.altitude map_info.speed map_info.radius map_info.center map_info.place map_info.area map_info.place_name_locked messages.edit messages.delete messages.anomaly_point areas.confirm_delete_named map.confirm_delete_point_permanently points.address.address)

  @toast_keys ~w(common.upgrade_to_pro common.dismiss messages.failed_to_update_settings common.and family.loaded_members hexagons.limit_warning hexagons.load_failed layer_preview.ended layer_preview.remaining layer_preview.started live_map.disabled live_map.enabled messages.api_key_not_available_please_reload_the_page messages.area_created_successfully messages.area_deleted_successfully messages.area_drawer_controller_not_available messages.cannot_update_recalculation_is_already_in_progress messages.centered_on_family_member messages.click_on_the_map_to_place_a_place messages.click_on_the_map_to_place_a_visit_esc_to messages.confirming_visits messages.connected_to_real_time_updates messages.could_not_queue_re_evaluation_please_try_again messages.could_not_queue_recalculation_please_try_again messages.deleting_anomaly_points messages.deleting_area messages.deleting_points messages.deleting_visits messages.disconnected_from_real_time_updates messages.draw_a_rectangle_on_the_map_to_select_points messages.failed_to_confirm_visit messages.failed_to_delete_area messages.failed_to_delete_point messages.failed_to_delete_visits messages.failed_to_fetch_data_in_selected_area messages.failed_to_load_anomalies messages.failed_to_load_area_details messages.failed_to_load_areas messages.failed_to_load_family_members messages.failed_to_load_flights messages.failed_to_load_location_data_please_try_again messages.failed_to_load_photos messages.failed_to_load_place_details messages.failed_to_load_track_details messages.failed_to_load_track_points messages.failed_to_load_visit_details messages.failed_to_reload_areas messages.family_feature_not_available messages.fetching_data_in_selected_area messages.globe_view_will_be_applied_after_page_reload messages.merging_visits messages.new_location_recorded messages.no_anomaly_points_in_selection messages.no_data_found_in_selected_area messages.no_points_selected messages.point_deleted_successfully messages.select_at_least_2_visits_to_merge messages.selection_cancelled messages.settings_updated_successfully messages.some_photo_sources_unavailable messages.tracks_pending messages.transportation_settings_saved messages.visit_confirmed messages.visit_creation_controller_not_available messages.visit_creation_modal_not_available messages.visit_deleted messages.visits_merged_successfully selection.anomaly_points_deleted selection.map_refresh_failed selection.points_deleted selection.selected selection.too_many_points selection.too_many_selected_points selection.write_api_requires_pro settings.custom_style_load_failed settings.invalid_tile_url settings.re_evaluation_queued settings.recalculation_queued settings.transportation_recalculation_started visits.confirmed_count visits.deleted_count)

  def labels(locale) do
    bindings =
      Map.new(
        ~w(count id speed current total latitude longitude query hours minutes first last name layer seconds items error requested limit sources),
        &{&1, "{#{&1}}"}
      )

    (@keys ++ @toast_keys)
    |> Enum.flat_map(fn key ->
      path =
        case key do
          "replay.no_data_loaded" -> "shared.replay_panel.no_data_loaded"
          "points.address.address" -> key
          _ -> "javascript." <> key
        end

      other = text(locale, path, bindings) || key
      one = text(locale, path, Map.put(bindings, "count", 1))

      if one && one != String.replace(other, "{count}", "1"),
        do: [{key, other}, {key <> ".one", one}],
        else: [{key, other}]
    end)
    |> Map.new()
    |> Map.merge(family_labels(locale))
  end

  defp text(locale, path, bindings) do
    case Dawarich.I18n.t(locale, path, bindings) do
      {:ok, text} -> text |> LazyHTML.from_fragment() |> LazyHTML.text()
      _ -> nil
    end
  end

  defp family_labels(locale) do
    for scope <- ~w(sharing_since loaded_members),
        {kind, count} <- [{"one", 1}, {"other", "{count}"}],
        into: %{} do
      {:ok, text} =
        Dawarich.I18n.t(locale, "javascript.family.#{scope}", %{
          "count" => count,
          "date" => "{date}"
        })

      {"family.#{scope}.#{kind}", text |> LazyHTML.from_fragment() |> LazyHTML.text()}
    end
  end
end

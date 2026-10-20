defmodule DawarichWeb.NativeMapLabels do
  @moduledoc false
  @keys ~w(common.unknown family.none_sharing messages.retry messages.failed_to_load_map_tiles messages.failed_to_load_visited_countries common.confirm common.delete common.close common.not_available visits.selected visits.merge visits.none_found visits.none_found_for selection.points selection.visits selection.confirm_delete_points selection.delete_anomaly_points selection.confirm_delete_anomaly_points selection.delete_points_failed messages.failed_to_confirm_visits messages.failed_to_delete_visit messages.failed_to_merge_visits messages.point_label messages.edit_history messages.edit_history_capacity messages.undo messages.redo messages.redo_to_here messages.undo_to_here messages.point_edit_conflict messages.failed_to_update_point_position_please_try_again replay.no_data_loaded replay.no_data_at_this_time replay.speed replay.day_count replay.point_count search.unnamed_location search.searching_for_visits search.locations_found search.visits_load_failed map_info.location_coordinates map_info.overlapping_points selection.delete_points selection.visits_in_area visits.unnamed map_info.duration_hours_minutes map_info.duration_minutes visit_statuses.confirmed visit_statuses.declined visit_statuses.suggested search.searching search.no_locations search.suggestions_failed search.unknown_location search.first_last search.for_query map_info.location_point map_info.coordinates map_info.time map_info.battery map_info.altitude map_info.speed map_info.radius map_info.center map_info.place map_info.area map_info.place_name_locked messages.edit messages.delete messages.anomaly_point areas.confirm_delete_named map.confirm_delete_point_permanently points.address.address)

  def labels(locale) do
    bindings =
      Map.new(
        ~w(count id speed current total latitude longitude query hours minutes first last name),
        &{&1, "{#{&1}}"}
      )

    @keys
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

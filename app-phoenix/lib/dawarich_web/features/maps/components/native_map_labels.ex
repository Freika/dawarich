defmodule DawarichWeb.NativeMapLabels do
  @moduledoc false
  @keys ~w(common.confirm common.delete common.close common.not_available visits.selected visits.merge visits.none_found visits.none_found_for selection.points selection.visits selection.confirm_delete_points selection.delete_anomaly_points selection.confirm_delete_anomaly_points selection.delete_points_failed messages.failed_to_confirm_visits messages.failed_to_delete_visit messages.failed_to_merge_visits messages.point_label messages.edit_history messages.edit_history_capacity messages.undo messages.redo messages.redo_to_here messages.undo_to_here messages.point_edit_conflict messages.failed_to_update_point_position_please_try_again replay.no_data_loaded replay.no_data_at_this_time replay.speed replay.day_count search.unnamed_location search.searching_for_visits search.locations_found search.visits_load_failed map_info.location_coordinates)

  def labels(locale) do
    bindings =
      Map.new(~w(count id speed current total latitude longitude query), &{&1, "{#{&1}}"})

    Map.new(@keys, fn key ->
      path =
        if key == "replay.no_data_loaded",
          do: "shared.replay_panel.no_data_loaded",
          else: "javascript." <> key

      value =
        case Dawarich.I18n.t(locale, path, bindings) do
          {:ok, text} -> text |> LazyHTML.from_fragment() |> LazyHTML.text()
          _ -> key
        end

      {key, value}
    end)
    |> Map.merge(family_labels(locale))
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

defmodule DawarichWeb.VisitRequest do
  @moduledoc false
  import DawarichWeb.A8Request, only: [member: 4, nested?: 3, root?: 2]
  @visit ~w(name place_id area_id started_at ended_at status)
  @settings ~w(visit_radius_meters visit_min_points visit_min_duration_minutes)

  def target(["settings", "visits"]), do: {:settings_update, ["PATCH", "PUT", "POST"], "PATCH"}
  def target(["visits", "redetections"]), do: {:redetect, ["POST"], "POST"}
  def target(["visits", "bulk_update"]), do: {:bulk_update, ["PATCH", "POST"], "PATCH"}
  def target(["visits", "bulk_destroy"]), do: {:bulk_destroy, ["DELETE", "POST"], "DELETE"}
  def target(["visits", "merge"]), do: {:merge, ["POST"], "POST"}

  def target(["visits", id]),
    do: member(id, :visit, ["PATCH", "PUT", "DELETE", "POST"], ~w(PATCH DELETE))

  def target(_), do: nil

  def action(:visit, "DELETE"), do: :visit_destroy
  def action(:visit, _), do: :visit_update
  def action(action, _method), do: action

  def fields?(:settings_update, params), do: nested?(params, "settings", @settings)

  def fields?(:visit_update, params), do: nested?(params, "visit", @visit)

  def fields?(action, params) when action in [:bulk_update, :bulk_destroy, :merge] do
    root?(params, ~w(visit_ids status source_status date)) and
      Enum.all?(params, fn
        {"visit_ids", list} when is_list(list) -> Enum.all?(list, &is_binary/1)
        {_, value} -> is_binary(value)
      end)
  end

  def fields?(action, params) when action in [:visit_destroy, :redetect], do: root?(params, [])

  def fields?(_, _), do: false

  def query_keys(_), do: []
  def repeated_keys, do: ["visit_ids[]"]
end

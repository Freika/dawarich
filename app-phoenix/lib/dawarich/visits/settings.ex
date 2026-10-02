defmodule Dawarich.Visits.Settings do
  @moduledoc false

  alias Dawarich.RubyInteger

  @defaults %{
    "visit_radius_meters" => 100,
    "visit_min_points" => 3,
    "visit_min_duration_minutes" => 5,
    "merge_threshold_minutes" => 15,
    "visits_suggestions_enabled" => "true"
  }

  def load(repo, user_id) do
    case repo.query!("SELECT settings FROM users WHERE id = $1", [user_id], log: false).rows do
      [[settings]] -> %{id: user_id, settings: settings}
      [] -> nil
    end
  end

  def policy(settings) do
    get = &Map.get(merged(settings), &1)

    %{
      stay_radius_m: clamp(RubyInteger.to_i(get.("visit_radius_meters")), 5, 500),
      min_dwell_s: clamp(RubyInteger.to_i(get.("visit_min_duration_minutes") || 5), 1, 60) * 60,
      min_points: clamp(RubyInteger.to_i(get.("visit_min_points")), 2, 20),
      merge_gap_s: RubyInteger.to_i(get.("merge_threshold_minutes")) * 60,
      suggestions_enabled: get.("visits_suggestions_enabled") == "true",
      sweep_gap_s: 3600,
      bridge_cap_s: 604_800,
      snap_max_s: 900,
      attribution_radius_m: 50
    }
  end

  defp merged(%{} = settings), do: Map.merge(@defaults, settings)
  defp merged(_settings), do: @defaults

  defp clamp(value, low, high), do: value |> max(low) |> min(high)
end

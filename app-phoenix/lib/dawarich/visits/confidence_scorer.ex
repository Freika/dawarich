defmodule Dawarich.Visits.ConfidenceScorer do
  @moduledoc false

  alias Dawarich.RubyFloat

  @target_dwell_seconds 1800
  @default_accuracy 50.0
  @weights %{
    dwell: 0.30,
    tightness: 0.25,
    place_match: 0.20,
    density: 0.15,
    accuracy: 0.10,
    bridged: 0.15,
    corroboration: 0.10
  }
  @place_match_scores %{area: 1.0, place: 0.85, poi: 0.6, address: 0.35}

  def score(input) do
    duration = input.duration_seconds * 1.0
    radius = input.radius_meters * 1.0
    stay_radius = input.stay_radius_meters * 1.0
    min_points = max(input.min_points, 1)

    subs =
      [
        dwell: clamp(duration / @target_dwell_seconds),
        tightness: if(stay_radius <= 0, do: 0.0, else: clamp(1.0 - radius / stay_radius)),
        density: clamp(input.point_count / (min_points * 3.0)),
        accuracy: clamp(1.0 - (median(input.accuracies) - 10.0) / 90.0)
      ] ++
        optional(:place_match, input[:place_match], &Map.get(@place_match_scores, &1, 0.0)) ++
        optional(:bridged, input[:bridged_fraction], &clamp(1.0 - &1 * 1.0)) ++
        optional(:corroboration, input[:corroborated], &if(&1, do: 1.0, else: 0.5))

    total_weight = subs |> Enum.map(fn {key, _} -> @weights[key] end) |> RubyFloat.sum()

    weighted =
      subs
      |> Enum.map(fn {key, value} -> @weights[key] / total_weight * value end)
      |> RubyFloat.sum()

    %{
      score: (weighted * 100) |> RubyFloat.round() |> max(0) |> min(100),
      breakdown: breakdown(subs, input)
    }
  end

  defp optional(_key, nil, _fun), do: []
  defp optional(key, value, fun), do: [{key, fun.(value)}]

  defp breakdown(subs, input) do
    rounded = for {key, value} <- subs, do: {Atom.to_string(key), RubyFloat.round(value, 3)}
    if input[:place_match] == nil, do: rounded ++ [{"place_match", "unavailable"}], else: rounded
  end

  defp median(accuracies) do
    values =
      accuracies |> Enum.map(&if(&1 == nil, do: @default_accuracy, else: &1 * 1.0)) |> Enum.sort()

    mid = div(length(values), 2)

    cond do
      values == [] -> @default_accuracy
      rem(length(values), 2) == 1 -> Enum.at(values, mid)
      true -> (Enum.at(values, mid - 1) + Enum.at(values, mid)) / 2.0
    end
  end

  defp clamp(value) when value < 0.0, do: 0.0
  defp clamp(value) when value > 1.0, do: 1.0
  defp clamp(value), do: value
end

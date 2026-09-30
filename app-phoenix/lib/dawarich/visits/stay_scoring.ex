defmodule Dawarich.Visits.StayScoring do
  @moduledoc false

  alias Dawarich.RubyInteger
  alias Dawarich.Visits.ConfidenceScorer

  def attributes(stay, points_by_id, policy) do
    duration = stay.duration_s

    result =
      ConfidenceScorer.score(%{
        duration_seconds: duration,
        point_count: stay.count,
        accuracies:
          for(id <- stay.point_ids, p = points_by_id[id], p.accuracy != nil, do: p.accuracy),
        radius_meters: stay.radius,
        stay_radius_meters: policy.stay_radius_m,
        min_points: policy.min_points,
        place_match: if(stay.evidence == :none, do: nil, else: stay.evidence),
        bridged_fraction:
          if(duration > 0, do: RubyInteger.to_i(stay.bridged_s) / duration, else: 0.0),
        corroborated: stay.corroborated
      })

    %{confidence: result.score, confidence_breakdown: result.breakdown}
  end
end

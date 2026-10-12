# frozen_string_literal: true

module Visits
  module Detection
    # Scores a stay hash after attribution — shared by the Runner's initial
    # pass and the Persister's post-trim rescore, so a stay's confidence
    # always reflects the interval actually persisted.
    module StayScoring
      module_function

      def attributes(stay, points_by_id, policy)
        result = Visits::ConfidenceScorer.new(
          duration_seconds: stay[:duration_s],
          point_count: stay[:count],
          accuracies: stay[:point_ids].filter_map { |id| points_by_id[id]&.accuracy },
          radius_meters: stay[:radius],
          stay_radius_meters: policy.stay_radius_m,
          min_points: policy.min_points,
          place_match: stay[:evidence] == :none ? nil : stay[:evidence],
          bridged_fraction: stay[:duration_s].positive? ? stay[:bridged_s].to_i.fdiv(stay[:duration_s]) : 0.0,
          corroborated: stay[:corroborated]
        ).call

        { confidence: result[:score], confidence_breakdown: result[:breakdown] }
      end
    end
  end
end

# frozen_string_literal: true

module Visits
  class ConfidenceScorer
    TARGET_DWELL_SECONDS = 1800
    DEFAULT_ACCURACY_METERS = 50

    WEIGHTS = {
      dwell: 0.30,
      tightness: 0.25,
      place_match: 0.20,
      density: 0.15,
      accuracy: 0.10
    }.freeze

    PLACE_MATCH_SCORES = { area: 1.0, place: 0.7 }.freeze

    def initialize(duration_seconds:, point_count:, accuracies:, radius_meters:,
                   stay_radius_meters:, min_points:, place_match: nil)
      @duration_seconds = duration_seconds.to_f
      @point_count = point_count.to_i
      @accuracies = Array(accuracies)
      @radius_meters = radius_meters.to_f
      @stay_radius_meters = stay_radius_meters.to_f
      @min_points = [min_points.to_i, 1].max
      @place_match = place_match
    end

    def call
      subs = {
        dwell: dwell_score,
        tightness: tightness_score,
        density: density_score,
        accuracy: accuracy_score
      }
      subs[:place_match] = place_match_score unless @place_match.nil?

      score = (weighted(subs) * 100).round.clamp(0, 100)
      { score: score, breakdown: breakdown(subs) }
    end

    private

    # Redistribute weights over only the components actually present, so a missing
    # place-match doesn't cap the score (it just isn't counted).
    def weighted(subs)
      total_weight = subs.keys.sum { |key| WEIGHTS[key] }
      subs.sum { |key, value| (WEIGHTS[key] / total_weight) * value }
    end

    def dwell_score
      clamp(@duration_seconds / TARGET_DWELL_SECONDS)
    end

    def density_score
      clamp(@point_count / (@min_points * 3.0))
    end

    def accuracy_score
      clamp(1.0 - ((median_accuracy - 10.0) / 90.0))
    end

    # @radius_meters is the max point-to-center distance (from ClusterHelper#calculate_visit_radius),
    # not RMS / radius-of-gyration — so tightness is slightly harsher than a gyration-based measure.
    def tightness_score
      return 0.0 if @stay_radius_meters <= 0

      clamp(1.0 - (@radius_meters / @stay_radius_meters))
    end

    def place_match_score
      PLACE_MATCH_SCORES.fetch(@place_match, 0.0)
    end

    def median_accuracy
      values = @accuracies.map { |a| a.nil? ? DEFAULT_ACCURACY_METERS : a.to_f }.sort
      return DEFAULT_ACCURACY_METERS.to_f if values.empty?

      mid = values.size / 2
      values.size.odd? ? values[mid] : (values[mid - 1] + values[mid]) / 2.0
    end

    def breakdown(subs)
      rounded = subs.transform_values { |value| value.round(3) }
      rounded[:place_match] = 'unavailable' if @place_match.nil?
      rounded
    end

    def clamp(value)
      value.clamp(0.0, 1.0)
    end
  end
end

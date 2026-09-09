# frozen_string_literal: true

module TransportationModes
  # Scores predicted transportation segments against ground-truth labels.
  # Used by the eval specs (spec/eval) to measure detection quality.
  module EvalScorer
    BOUNDARY_TOLERANCE_S = 60

    module_function

    # @param predicted [Array<Hash>] [{mode:, start_ts:, end_ts:}]
    # @param labels [Array<Hash>] same shape, ground truth
    # @param points [Array<Hash>] [{timestamp:}] evaluation sample points
    # @return [Hash] { point_accuracy:, boundary_f1:, per_mode: }
    def score(predicted:, labels:, points:)
      pairs = points.map { |p| [mode_at(predicted, p[:timestamp]), mode_at(labels, p[:timestamp])] }
      scored = pairs.reject { |_pred, truth| truth.nil? }
      matches = scored.count { |pred, truth| pred == truth }

      {
        point_accuracy: scored.empty? ? 0.0 : (matches.to_f / scored.size).round(4),
        boundary_f1: boundary_f1(predicted, labels),
        per_mode: per_mode_stats(scored)
      }
    end

    def mode_at(segments, timestamp)
      segment = segments.find { |s| timestamp >= s[:start_ts] && timestamp < s[:end_ts] }
      segment ||= segments.last if segments.any? && timestamp == segments.last[:end_ts]
      segment && segment[:mode]
    end

    def boundary_f1(predicted, labels)
      predicted_bounds = internal_boundaries(predicted)
      label_bounds = internal_boundaries(labels)
      return 1.0 if predicted_bounds.empty? && label_bounds.empty?
      return 0.0 if predicted_bounds.empty? || label_bounds.empty?

      matched = greedy_match_count(predicted_bounds, label_bounds)
      precision = matched.to_f / predicted_bounds.size
      recall = matched.to_f / label_bounds.size
      return 0.0 if (precision + recall).zero?

      (2 * precision * recall / (precision + recall)).round(4)
    end

    def internal_boundaries(segments)
      segments.each_cons(2).map { |_a, b| b[:start_ts] }
    end

    def greedy_match_count(predicted_bounds, label_bounds)
      available = label_bounds.dup
      predicted_bounds.count do |pb|
        idx = available.index { |lb| (lb - pb).abs <= BOUNDARY_TOLERANCE_S }
        available.delete_at(idx) if idx
        !idx.nil?
      end
    end

    def per_mode_stats(scored_pairs)
      modes = (scored_pairs.map(&:first) + scored_pairs.map(&:last)).compact.uniq
      modes.index_with do |mode|
        predicted_count = scored_pairs.count { |pred, _t| pred == mode }
        truth_count = scored_pairs.count { |_p, truth| truth == mode }
        correct = scored_pairs.count { |pred, truth| pred == mode && truth == mode }
        {
          precision: predicted_count.zero? ? 0.0 : (correct.to_f / predicted_count).round(4),
          recall: truth_count.zero? ? 0.0 : (correct.to_f / truth_count).round(4)
        }
      end
    end
  end
end

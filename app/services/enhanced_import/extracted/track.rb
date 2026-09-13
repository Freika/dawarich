# frozen_string_literal: true

module EnhancedImport
  module Extracted
    Track = Data.define(
      :tracker_id,
      :start_at,
      :end_at,
      :distance_m,
      :transportation_mode,
      :confidence,
      :source_label,
      :segments
    ) do
      def initialize(tracker_id:, start_at:, end_at:, distance_m: nil,
                     transportation_mode: nil, confidence: nil,
                     source_label: nil, segments: [])
        super
      end
    end
  end
end

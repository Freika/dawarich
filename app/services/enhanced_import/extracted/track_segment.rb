# frozen_string_literal: true

module EnhancedImport
  module Extracted
    TrackSegment = Data.define(
      :start_index,
      :end_index,
      :transportation_mode,
      :confidence,
      :source_label
    ) do
      def initialize(start_index:, end_index:, transportation_mode:, confidence: nil, source_label: nil)
        super
      end
    end
  end
end

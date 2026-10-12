# frozen_string_literal: true

module EnhancedImport
  module Extracted
    Visit = Data.define(
      :started_at,
      :ended_at,
      :place,
      :name,
      :confidence,
      :source_label
    ) do
      def initialize(started_at:, ended_at:, place:, name: nil, confidence: nil, source_label: nil)
        super
      end

      def duration_seconds
        (ended_at - started_at).to_i
      end
    end
  end
end

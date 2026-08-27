# frozen_string_literal: true

module EnhancedImport
  module Extracted
    Place = Data.define(
      :external_place_id,
      :name,
      :latitude,
      :longitude,
      :semantic_type,
      :geodata_extras
    ) do
      def initialize(external_place_id:, name:, latitude:, longitude:, semantic_type: nil, geodata_extras: {})
        super
      end
    end
  end
end

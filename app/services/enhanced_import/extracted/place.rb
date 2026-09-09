# frozen_string_literal: true

module EnhancedImport
  module Extracted
    Place = Data.define(
      :external_place_id,
      :name,
      :latitude,
      :longitude,
      :semantic_type,
      :geodata_extras,
      :tag_name,
      :tag_color
    ) do
      def initialize(external_place_id:, name:, latitude:, longitude:, semantic_type: nil,
                     geodata_extras: {}, tag_name: nil, tag_color: nil)
        super
      end
    end
  end
end

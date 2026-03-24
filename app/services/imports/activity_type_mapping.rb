# frozen_string_literal: true

module Imports
  module ActivityTypeMapping
    MAPPING = {
      # Google Semantic Segments
      'IN_PASSENGER_VEHICLE' => 'driving',
      'WALKING' => 'walking',
      'CYCLING' => 'cycling',
      'RUNNING' => 'running',
      'FLYING' => 'flying',
      'IN_BUS' => 'bus',
      'IN_TRAIN' => 'train',
      # TCX Sport types
      'Running' => 'running',
      'Biking' => 'cycling',
      # FIT sport types
      'running' => 'running',
      'trail_running' => 'running',
      'cycling' => 'cycling',
      'mountain_biking' => 'cycling',
      'walking' => 'walking',
      'hiking' => 'walking',
      'driving' => 'driving',
      'flying' => 'flying'
    }.freeze

    def map_activity_type(source_type)
      return nil if source_type.nil?

      MAPPING[source_type.to_s]
    end
  end
end

# frozen_string_literal: true

module MapMatching
  module ModeMapper
    MODES = {
      'walking' => 'pedestrian',
      'running' => 'pedestrian',
      'cycling' => 'bicycle',
      'driving' => 'auto',
      'bus' => 'auto',
      'motorcycle' => 'auto'
    }.freeze

    def self.call(mode)
      MODES[mode.to_s]
    end
  end
end

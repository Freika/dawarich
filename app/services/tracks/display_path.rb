# frozen_string_literal: true

module Tracks
  module DisplayPath
    VARIANTS = %w[original display matched compare].freeze

    def self.enabled?
      DawarichSettings.map_matching_enabled? && !Flipper.enabled?(:map_matching_shadow_mode)
    end

    def self.matched?(track)
      enabled? && track.map_matching_result? && track.map_matching_input_digest.present?
    end

    def self.for(track, variant: 'original')
      case variant.to_s
      when 'display' then matched?(track) ? track.matched_path : track.original_path
      when 'matched' then matched?(track) ? track.matched_path : nil
      else track.original_path
      end
    end
  end
end

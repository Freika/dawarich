# frozen_string_literal: true

module Imports
  module FieldAliases
    ALIASES = {
      latitude:          %w[lat latitude y y_pos],
      longitude:         %w[lon lng long longitude x x_pos],
      timestamp:         %w[timestamp time date datetime when created_at recorded_at fixTime tst],
      altitude:          %w[altitude alt ele elevation height z],
      speed:             %w[speed velocity vel speed_mps speed_kmh],
      accuracy:          %w[accuracy acc horizontal_accuracy hdop precision],
      vertical_accuracy: %w[vertical_accuracy vac vdop],
      battery:           %w[battery batt bat battery_level bs],
      heading:           %w[heading bearing course cog],
      tracker_id:        %w[tracker_id tid device_id device deviceId]
    }.freeze

    SPEED_KMH_ALIASES = %w[speed_kmh].freeze

    def find_field(hash, canonical_name)
      aliases = ALIASES[canonical_name]
      return nil unless aliases

      aliases.each do |key|
        [key, key.downcase, key.upcase, key.capitalize, key.to_sym, key.downcase.to_sym].each do |variant|
          return hash[variant] if hash.key?(variant)
        end
      end
      nil
    end

    def find_field_with_key(hash, canonical_name)
      aliases = ALIASES[canonical_name]
      return [nil, nil] unless aliases

      aliases.each do |key|
        [key, key.downcase, key.upcase, key.capitalize, key.to_sym, key.downcase.to_sym].each do |variant|
          return [hash[variant], key] if hash.key?(variant)
        end
      end
      [nil, nil]
    end

    def find_header(headers, canonical_name)
      aliases = ALIASES[canonical_name]
      return nil unless aliases

      normalized = headers.map { |h| h.to_s.downcase.strip }
      aliases.each do |key|
        idx = normalized.index(key.downcase)
        return idx if idx
      end
      nil
    end

    def speed_kmh_alias?(matched_alias)
      SPEED_KMH_ALIASES.include?(matched_alias.to_s.downcase)
    end
  end
end

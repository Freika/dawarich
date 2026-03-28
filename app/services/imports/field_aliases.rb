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

    # Pre-computed reverse lookup: variant → [canonical_name, original_alias_key]
    # Eliminates 60 hash lookups per field per point, replacing with a single lookup.
    REVERSE_LOOKUP = begin
      table = {}
      ALIASES.each do |canonical, keys|
        keys.each do |key|
          [key, key.downcase, key.upcase, key.capitalize, key.to_sym, key.downcase.to_sym].each do |variant|
            table[variant] ||= [canonical, key]
          end
        end
      end
      table.freeze
    end

    def find_field(hash, canonical_name)
      hash.each_key do |key|
        entry = REVERSE_LOOKUP[key]
        return hash[key] if entry && entry[0] == canonical_name
      end
      nil
    end

    def find_field_with_key(hash, canonical_name)
      hash.each_key do |key|
        entry = REVERSE_LOOKUP[key]
        return [hash[key], entry[1]] if entry && entry[0] == canonical_name
      end
      [nil, nil]
    end

    def find_header(headers, canonical_name)
      normalized = headers.map { |h| h.to_s.downcase.strip }
      aliases = ALIASES[canonical_name]
      return nil unless aliases

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

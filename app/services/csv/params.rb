# frozen_string_literal: true

module Csv
  class Params
    def initialize(row, detection, user_id, import_id)
      @row = row
      @columns = detection[:columns]
      @coordinate_format = detection[:coordinate_format]
      @timestamp_format = detection[:timestamp_format]
      @comma_decimals = detection[:comma_decimals]
      @user_id = user_id
      @import_id = import_id
    end

    def call
      lat = parse_latitude
      lon = parse_longitude
      timestamp = parse_timestamp

      return nil if lat.nil? || lon.nil? || timestamp.nil?

      altitude_value = parse_float(:altitude)

      attrs = {
        lonlat: "POINT(#{lon} #{lat})",
        timestamp: timestamp,
        altitude: altitude_value,
        velocity: parse_float(:speed),
        accuracy: parse_float(:accuracy),
        battery: parse_float(:battery),
        course: parse_float(:heading),
        tracker_id: field_value(:tracker_id),
        user_id: @user_id,
        import_id: @import_id,
        created_at: Time.current,
        updated_at: Time.current
      }
      attrs[:altitude_decimal] = altitude_value if Point.altitude_decimal_supported?
      attrs
    end

    private

    def field_value(canonical)
      idx = @columns[canonical]
      return nil if idx.nil?

      value = @row[idx]&.strip
      value.presence
    end

    def parse_float(canonical)
      value = field_value(canonical)
      return nil if value.nil?

      value = value.gsub(',', '.') if @comma_decimals
      value.to_f
    end

    def parse_latitude
      value = field_value(:latitude)
      return nil if value.blank?

      value = value.gsub(',', '.') if @comma_decimals
      parse_coordinate(value, :lat)
    end

    def parse_longitude
      value = field_value(:longitude)
      return nil if value.blank?

      value = value.gsub(',', '.') if @comma_decimals
      parse_coordinate(value, :lon)
    end

    def parse_coordinate(value, _axis)
      case @coordinate_format
      when :e7
        value.to_f / 10_000_000.0
      when :directional
        num = value.gsub(/[NSEW]/i, '').to_f
        num *= -1 if value.match?(/[SW]/i)
        num
      else
        value.to_f
      end
    end

    def parse_timestamp
      value = field_value(:timestamp)
      return nil if value.blank?

      case @timestamp_format
      when :unix_seconds
        Time.zone.at(value.to_i).to_i
      when :unix_milliseconds
        Time.zone.at(value.to_i / 1000.0).to_i
      else
        Time.zone.parse(value).to_i
      end
    rescue ArgumentError
      nil
    end
  end
end

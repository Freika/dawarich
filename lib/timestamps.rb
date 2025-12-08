# frozen_string_literal: true

module Timestamps
  MIN_TIMESTAMP = Time.zone.parse('1970-01-01').to_i
  MAX_TIMESTAMP = Time.zone.parse('2100-01-01').to_i

  def self.parse_timestamp(timestamp)
    parsed = DateTime.parse(timestamp).to_time.to_i

    parsed.clamp(MIN_TIMESTAMP, MAX_TIMESTAMP)
  rescue StandardError
    result =
      if timestamp.to_s.length > 10
        timestamp.to_i / 1000
      else
        timestamp.to_i
      end

    result.clamp(MIN_TIMESTAMP, MAX_TIMESTAMP)
  end
end

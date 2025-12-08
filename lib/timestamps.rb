# frozen_string_literal: true

module Timestamps
  def self.parse_timestamp(timestamp)
    min_timestamp = Time.zone.parse('1970-01-01').to_i
    max_timestamp = Time.zone.parse('2100-01-01').to_i

    parsed = DateTime.parse(timestamp).to_time.to_i

    parsed.clamp(min_timestamp, max_timestamp)
  rescue StandardError
    result =
      if timestamp.to_s.length > 10
        timestamp.to_i / 1000
      else
        timestamp.to_i
      end

    result.clamp(min_timestamp, max_timestamp)
  end
end

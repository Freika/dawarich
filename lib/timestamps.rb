# frozen_string_literal: true

module Timestamps
  def self.parse_timestamp(timestamp)
    min_timestamp = Time.utc(1970, 1, 1).to_i
    max_timestamp = Time.utc(2100, 1, 1).to_i

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

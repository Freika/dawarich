# frozen_string_literal: true

class Points::TimestampParser
  class InvalidTimestampError < ArgumentError; end

  MIN_TIMESTAMP = -2_147_483_648
  MAX_TIMESTAMP = 2_147_483_647

  def self.call(value)
    return if value.blank?

    string = value.to_s
    parsed = if string.match?(/\A-?\d+\z/)
               timestamp = Integer(string, 10)
               Time.at(timestamp).utc.to_datetime
             else
               DateTime.iso8601(string)
             end

    raise InvalidTimestampError unless parsed.to_time.to_i.between?(MIN_TIMESTAMP, MAX_TIMESTAMP)

    parsed
  rescue ArgumentError, TypeError
    raise InvalidTimestampError, 'Timestamp must be ISO 8601 or Unix seconds'
  end
end

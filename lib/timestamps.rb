# frozen_string_literal: true

module Timestamps

  def self.parse_timestamp(timestamp)
    begin
      # if the timestamp is in ISO 8601 format, try to parse it
      DateTime.parse(timestamp).to_time.to_i
    rescue
      if timestamp.to_s.length > 10
        # If the timestamp is in milliseconds, convert to seconds
        timestamp.to_i / 1000
      else
        # If the timestamp is in seconds, return it without change
        timestamp.to_i
      end
    end
  end
end

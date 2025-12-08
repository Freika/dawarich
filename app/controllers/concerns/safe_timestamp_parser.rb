# frozen_string_literal: true

module SafeTimestampParser
  extend ActiveSupport::Concern

  private

  def safe_timestamp(date_string)
    parsed_time = Time.zone.parse(date_string)
    min_timestamp = Time.zone.parse('1970-01-01').to_i
    max_timestamp = Time.zone.parse('2100-01-01').to_i

    parsed_time.to_i.clamp(min_timestamp, max_timestamp)
  rescue ArgumentError
    Time.zone.now.to_i
  end
end

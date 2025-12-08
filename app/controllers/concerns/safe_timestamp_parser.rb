# frozen_string_literal: true

module SafeTimestampParser
  extend ActiveSupport::Concern

  private

  def safe_timestamp(date_string)
    return Time.zone.now.to_i if date_string.blank?

    parsed_time = Time.zone.parse(date_string)

    # Time.zone.parse returns epoch time (2000-01-01) for unparseable strings
    # Check if it's a valid parse by seeing if year is suspiciously at epoch
    return Time.zone.now.to_i if parsed_time.nil? || (parsed_time.year == 2000 && !date_string.include?('2000'))

    min_timestamp = Time.zone.parse('1970-01-01').to_i
    max_timestamp = Time.zone.parse('2100-01-01').to_i

    parsed_time.to_i.clamp(min_timestamp, max_timestamp)
  rescue ArgumentError, TypeError
    Time.zone.now.to_i
  end
end

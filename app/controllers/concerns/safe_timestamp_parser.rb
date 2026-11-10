# frozen_string_literal: true

module SafeTimestampParser
  extend ActiveSupport::Concern

  private

  def safe_timestamp(value)
    strict_timestamp(value) || Time.zone.now.to_i
  end

  # Nil for anything blank or unparseable, so a caller can tell a bad value from
  # a real one. Numeric strings are Unix timestamps.
  def strict_timestamp(value)
    return nil if value.blank?
    return clamp_timestamp(value.to_i) if value.match?(/\A\d+\z/)

    parsed = Time.zone.parse(value)
    return nil if parsed.nil?
    # Time.zone.parse yields year-2000 epoch for unparseable strings
    return nil if parsed.year == 2000 && !value.include?('2000')

    clamp_timestamp(parsed.to_i)
  rescue ArgumentError, TypeError
    nil
  end

  def parse_time_param(value)
    Time.zone.parse(value.to_s) if value.present?
  rescue ArgumentError
    nil
  end

  def clamp_timestamp(value)
    value.clamp(Time.zone.parse('1970-01-01').to_i, Time.zone.parse('2100-01-01').to_i)
  end
end

# frozen_string_literal: true

# Helper module for timezone-aware date calculations.
# Provides consistent timezone handling for date boundaries across the application.
module TimezoneHelper
  DEFAULT_TIMEZONE = 'UTC'

  class << self
    # Returns [start_timestamp, end_timestamp] for a month in the given timezone.
    # All timestamps are Unix epochs representing the correct moment in time.
    def month_bounds(year, month, timezone)
      tz = resolve_timezone(timezone)
      start_time = tz.local(year, month, 1).beginning_of_day
      end_time = start_time.end_of_month.end_of_day
      [start_time.to_i, end_time.to_i]
    end

    # Returns [start_timestamp, end_timestamp] for a year in the given timezone.
    def year_bounds(year, timezone)
      tz = resolve_timezone(timezone)
      start_time = tz.local(year, 1, 1).beginning_of_day
      end_time = start_time.end_of_year.end_of_day
      [start_time.to_i, end_time.to_i]
    end

    # Returns [start_timestamp, end_timestamp] for a day in the given timezone.
    def day_bounds(date, timezone)
      tz = resolve_timezone(timezone)
      start_time = tz.local(date.year, date.month, date.day).beginning_of_day
      end_time = start_time.end_of_day
      [start_time.to_i, end_time.to_i]
    end

    # Converts a Unix timestamp to a Date in the given timezone.
    def timestamp_to_date(timestamp, timezone)
      tz = resolve_timezone(timezone)
      Time.at(timestamp).in_time_zone(tz).to_date
    end

    # Returns today's date in the given timezone.
    def today_in_timezone(timezone)
      tz = resolve_timezone(timezone)
      Time.current.in_time_zone(tz).to_date
    end

    # Returns today's beginning of day timestamp in the given timezone.
    def today_start_timestamp(timezone)
      tz = resolve_timezone(timezone)
      Time.current.in_time_zone(tz).beginning_of_day.to_i
    end

    # Returns today's end of day timestamp in the given timezone.
    def today_end_timestamp(timezone)
      tz = resolve_timezone(timezone)
      Time.current.in_time_zone(tz).end_of_day.to_i
    end

    # Returns the start of a month as a Time object in the given timezone.
    def month_start_time(year, month, timezone)
      tz = resolve_timezone(timezone)
      tz.local(year, month, 1).beginning_of_day
    end

    # Returns the end of a month as a Time object in the given timezone.
    def month_end_time(year, month, timezone)
      tz = resolve_timezone(timezone)
      tz.local(year, month, 1).end_of_month.end_of_day
    end

    # Returns the start of a year as a Time object in the given timezone.
    def year_start_time(year, timezone)
      tz = resolve_timezone(timezone)
      tz.local(year, 1, 1).beginning_of_day
    end

    # Returns the end of a year as a Time object in the given timezone.
    def year_end_time(year, timezone)
      tz = resolve_timezone(timezone)
      tz.local(year, 12, 31).end_of_day
    end

    # Returns a date range for a month (used for iterating over days).
    def month_date_range(year, month, timezone)
      tz = resolve_timezone(timezone)
      start_date = tz.local(year, month, 1).to_date
      end_date = tz.local(year, month, 1).end_of_month.to_date
      start_date..end_date
    end

    # Validates a timezone name and returns it if valid, or default if invalid.
    def validate_timezone(timezone)
      return DEFAULT_TIMEZONE if timezone.blank?
      return timezone if valid_timezone?(timezone)

      DEFAULT_TIMEZONE
    end

    # Returns true if the timezone name is valid.
    def valid_timezone?(timezone)
      return false if timezone.blank?

      ActiveSupport::TimeZone[timezone].present?
    end

    private

    def resolve_timezone(timezone)
      tz = ActiveSupport::TimeZone[timezone]
      return tz if tz.present?

      ActiveSupport::TimeZone[DEFAULT_TIMEZONE]
    end
  end
end

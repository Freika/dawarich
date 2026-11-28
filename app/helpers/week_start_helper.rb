# frozen_string_literal: true

module WeekStartHelper
  def week_start
    Current.date_time_preferences.week_start_symbol
  end

  def week_ordered(monday_first, start = week_start)
    start == :sunday ? monday_first.rotate(-1) : monday_first
  end
end

# frozen_string_literal: true

module Stats
  class BulkCalculator
    def initialize(user_id)
      @user_id = user_id
      @user = User.find(user_id)
    end

    def call
      months = extract_months(fetch_timestamps)

      schedule_calculations(months)
    end

    private

    attr_reader :user_id, :user

    def fetch_timestamps
      last_calculated_at = Stat.where(user_id:).maximum(:updated_at)
      last_calculated_at ||= DateTime.new(1970, 1, 1)

      time_diff = last_calculated_at.to_i..Time.current.to_i
      Point.where(user_id:, timestamp: time_diff).pluck(:timestamp).uniq
    end

    def extract_months(timestamps)
      timezone = user.timezone
      timestamps.group_by do |timestamp|
        date = TimezoneHelper.timestamp_to_date(timestamp, timezone)
        [date.year, date.month]
      end.keys
    end

    def schedule_calculations(months)
      months.each do |year, month|
        Stats::CalculatingJob.perform_later(user_id, year, month)
      end
    end
  end
end

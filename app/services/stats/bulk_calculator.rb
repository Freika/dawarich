# frozen_string_literal: true

module Stats
  class BulkCalculator
    def initialize(user_id)
      @user_id = user_id
    end

    def call
      schedule_calculations(fetch_months)
    end

    private

    attr_reader :user_id

    def user
      @user ||= User.find(user_id)
    end

    def fetch_months
      last_calculated_at = Stat.where(user_id:).maximum(:updated_at)
      last_calculated_at ||= DateTime.new(1970, 1, 1)

      start_ts = last_calculated_at.to_i
      end_ts = Time.current.to_i

      sql = Point.sanitize_sql_array([
        "SELECT DISTINCT " \
        "EXTRACT(YEAR FROM to_timestamp(timestamp) AT TIME ZONE ?)::int AS year, " \
        "EXTRACT(MONTH FROM to_timestamp(timestamp) AT TIME ZONE ?)::int AS month " \
        "FROM points WHERE user_id = ? AND timestamp BETWEEN ? AND ?",
        user.timezone, user.timezone, user_id, start_ts, end_ts
      ])

      Point.connection.select_rows(sql).map { |y, m| [y.to_i, m.to_i] }
    end

    def schedule_calculations(months)
      months.each do |year, month|
        Stats::CalculatingJob.perform_later(user_id, year, month)
      end
    end
  end
end

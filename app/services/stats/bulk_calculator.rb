# frozen_string_literal: true

module Stats
  class BulkCalculator
    STALE_STATS_PER_RUN = 5
    REPAIR_JITTER = 55.minutes

    def initialize(user_id)
      @user_id = user_id
    end

    def call
      swept_until = Time.current
      new_months = months_with_new_points(swept_until)

      schedule_calculations(new_months)
      schedule_repairs(stale_months - new_months)

      user.update_column(:stats_swept_at, swept_until)
    end

    private

    attr_reader :user_id

    def user
      @user ||= User.find(user_id)
    end

    def stale_months
      Stat.where(user_id:)
          .where(calculation_version: ...CalculateMonth::CALCULATION_VERSION)
          .order(Arel.sql('repair_deferred_at ASC NULLS FIRST'), :id)
          .limit(STALE_STATS_PER_RUN)
          .pluck(:year, :month)
    end

    def months_with_new_points(swept_until)
      start_ts = watermark.to_i
      end_ts = swept_until.to_i

      sql = Point.sanitize_sql_array([
                                       'SELECT DISTINCT ' \
                                       'EXTRACT(YEAR FROM to_timestamp(timestamp) AT TIME ZONE ?)::int AS year, ' \
                                       'EXTRACT(MONTH FROM to_timestamp(timestamp) AT TIME ZONE ?)::int AS month ' \
                                       'FROM points WHERE user_id = ? AND timestamp BETWEEN ? AND ?',
                                       user.timezone_iana, user.timezone_iana, user_id, start_ts, end_ts
                                     ])

      Point.connection.select_rows(sql).map { |y, m| [y.to_i, m.to_i] }
    end

    def watermark
      user.stats_swept_at ||
        Stat.where(user_id:).maximum(:updated_at) ||
        DateTime.new(1970, 1, 1)
    end

    def schedule_calculations(months)
      months.each do |year, month|
        Stats::CalculatingJob.perform_later(user_id, year, month)
      end
    end

    def schedule_repairs(months)
      months.each do |year, month|
        Stats::CalculatingJob
          .set(wait: rand(0..REPAIR_JITTER.to_i).seconds)
          .perform_later(user_id, year, month, notify_on_failure: false)
      end

      defer_repaired(months)
    end

    def defer_repaired(months)
      months.each do |year, month|
        Stat.where(user_id:, year:, month:).update_all(repair_deferred_at: Time.current)
      end
    end
  end
end

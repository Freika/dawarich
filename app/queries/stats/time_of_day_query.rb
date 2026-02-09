# frozen_string_literal: true

module Stats
  class TimeOfDayQuery
    TIME_PERIODS = {
      'night' => (0..5),       # 00:00-05:59
      'morning' => (6..11),    # 06:00-11:59
      'afternoon' => (12..17), # 12:00-17:59
      'evening' => (18..23)    # 18:00-23:59
    }.freeze

    def initialize(user, year, month = nil, timezone = 'UTC')
      @user = user
      @year = year.to_i
      @month = month&.to_i
      @timezone = validate_timezone(timezone)
    end

    def call
      result = execute_query
      normalize_to_percentages(result)
    end

    private

    attr_reader :user, :year, :month, :timezone

    def execute_query
      sql = <<~SQL
        SELECT
          CASE
            WHEN EXTRACT(HOUR FROM (to_timestamp(timestamp) AT TIME ZONE 'UTC' AT TIME ZONE '#{timezone}')) BETWEEN 0 AND 5 THEN 'night'
            WHEN EXTRACT(HOUR FROM (to_timestamp(timestamp) AT TIME ZONE 'UTC' AT TIME ZONE '#{timezone}')) BETWEEN 6 AND 11 THEN 'morning'
            WHEN EXTRACT(HOUR FROM (to_timestamp(timestamp) AT TIME ZONE 'UTC' AT TIME ZONE '#{timezone}')) BETWEEN 12 AND 17 THEN 'afternoon'
            ELSE 'evening'
          END as time_period,
          COUNT(*) as point_count
        FROM points
        WHERE user_id = #{user.id}
          AND timestamp >= #{start_timestamp}
          AND timestamp <= #{end_timestamp}
        GROUP BY time_period
      SQL

      ActiveRecord::Base.connection.execute(sql).to_a
    end

    def start_timestamp
      if month
        Time.zone.local(year, month, 1).beginning_of_month.to_i
      else
        Time.zone.local(year, 1, 1).beginning_of_year.to_i
      end
    end

    def end_timestamp
      if month
        Time.zone.local(year, month, 1).end_of_month.to_i
      else
        Time.zone.local(year, 12, 31).end_of_year.to_i
      end
    end

    def normalize_to_percentages(result)
      total = result.sum { |r| r['point_count'].to_i }
      return empty_result if total.zero?

      %w[night morning afternoon evening].each_with_object({}) do |period, hash|
        count = result.find { |r| r['time_period'] == period }&.dig('point_count').to_i || 0
        hash[period] = ((count.to_f / total) * 100).round
      end
    end

    def empty_result
      { 'night' => 0, 'morning' => 0, 'afternoon' => 0, 'evening' => 0 }
    end

    def validate_timezone(timezone_name)
      ActiveSupport::TimeZone.all.any? { |zone| zone.name == timezone_name } ? timezone_name : 'UTC'
    end
  end
end

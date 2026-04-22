# frozen_string_literal: true

module Timeline
  # Aggregates month-level activity for the calendar rail in the unified timeline.
  #
  # Produces a 6x7 grid of day cells with tracked activity (visits + tracks) grouped
  # in the user's timezone. Weeks start on Monday (European convention).
  #
  # Visit duration is stored in MINUTES; track duration is stored in SECONDS.
  # `tracked_seconds` normalizes both into seconds for intensity bucketing.
  class MonthSummary
    HEAT_THRESHOLDS_HOURS = [0, 2, 4, 8, 12].freeze
    CACHE_TTL = 5.minutes

    def self.cache_key_for(user, date)
      d = normalize_month(date)
      ['timeline_month_summary', user.id, d.strftime('%Y-%m')]
    end

    def self.heat_bucket(tracked_seconds)
      return 0 if tracked_seconds <= 0

      hours = tracked_seconds / 3600.0
      HEAT_THRESHOLDS_HOURS.each_with_index.reverse_each do |threshold, idx|
        return idx + 1 if hours >= threshold && idx < HEAT_THRESHOLDS_HOURS.length - 1
        return HEAT_THRESHOLDS_HOURS.length if hours >= HEAT_THRESHOLDS_HOURS.last
      end
      0
    end

    def self.normalize_month(date)
      if date.is_a?(String)
        Date.parse("#{date}-01")
      else
        date.to_date.beginning_of_month
      end
    end

    def initialize(user:, month:)
      @user = user
      @month_start = self.class.normalize_month(month)
    end

    def call
      Rails.cache.fetch(self.class.cache_key_for(@user, @month_start), expires_in: CACHE_TTL) do
        build_summary
      end
    end

    private

    def build_summary
      {
        month: @month_start.strftime('%Y-%m'),
        tz: tz,
        days: day_data,
        weeks: weeks
      }
    end

    def tz
      @tz ||= @user.safe_settings.timezone.presence || 'UTC'
    end

    def month_range
      @month_range ||= @month_start.in_time_zone(tz).all_month
    end

    def day_data
      @day_data ||= begin
        result = {}

        visit_rows.each do |(date_str, status), count|
          result[date_str] ||= default_day
          result[date_str][:visit_count] += count
          result[date_str]["#{status}_count".to_sym] += count if result[date_str].key?("#{status}_count".to_sym)
        end

        visit_minutes.each do |date_str, minutes|
          result[date_str] ||= default_day
          result[date_str][:tracked_seconds] += (minutes.to_i * 60)
        end

        track_seconds.each do |date_str, seconds|
          result[date_str] ||= default_day
          result[date_str][:tracked_seconds] += seconds.to_i
        end

        result
      end
    end

    def default_day
      {
        tracked_seconds: 0,
        visit_count: 0,
        suggested_count: 0,
        confirmed_count: 0,
        declined_count: 0
      }
    end

    def visit_rows
      @visit_rows ||= @user.scoped_visits
                           .where(started_at: month_range)
                           .group(date_sql_expr('visits.started_at'))
                           .group(:status)
                           .count
                           .transform_keys { |(date, status_int)| [date.to_s, visit_status_label(status_int)] }
    end

    def visit_minutes
      @visit_minutes ||= @user.scoped_visits
                              .where(started_at: month_range)
                              .group(date_sql_expr('visits.started_at'))
                              .sum(:duration)
                              .transform_keys(&:to_s)
    end

    def track_seconds
      @track_seconds ||= @user.scoped_tracks
                              .where(start_at: month_range)
                              .group(date_sql_expr('tracks.start_at'))
                              .sum(:duration)
                              .transform_keys(&:to_s)
    end

    def visit_status_label(status)
      return status.to_s if status.is_a?(String)

      Visit.statuses.key(status) || status.to_s
    end

    def date_sql_expr(column)
      quoted_tz = ActiveRecord::Base.connection.quote(tz)
      Arel.sql("DATE(#{column} AT TIME ZONE 'UTC' AT TIME ZONE #{quoted_tz})")
    end

    def weeks
      grid_start = @month_start.beginning_of_week(:monday)
      grid_end = grid_start + (6 * 7) - 1
      dates = (grid_start..grid_end).to_a

      dates.each_slice(7).map do |week|
        week.map { |date| build_cell(date) }
      end
    end

    def build_cell(date)
      key = date.strftime('%Y-%m-%d')
      data = day_data[key] || default_day

      {
        date: key,
        in_month: date.month == @month_start.month,
        tracked_seconds: data[:tracked_seconds],
        visit_count: data[:visit_count],
        suggested_count: data[:suggested_count],
        disabled: disabled_cell?(date)
      }
    end

    def disabled_cell?(date)
      return false unless @user.plan_restricted?

      cutoff = @user.data_window_start.to_date
      date < cutoff
    end
  end
end

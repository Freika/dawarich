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
    HEAT_BUCKETS = 5
    CACHE_TTL = 5.minutes

    # Fixed-threshold heat bucket for a single day, independent of the
    # month's max. Used by the calendar UI when it wants a stable bucket
    # value per day (`compute_heat_bucket` is month-relative; this one is
    # absolute). Thresholds match the rendered heat ramp:
    #   0           → 0
    #   < 2 hours   → 1
    #   2..4 hours  → 2
    #   4..8 hours  → 3
    #   8..12 hours → 4
    #   >= 12 hours → 5
    def self.heat_bucket(tracked_seconds)
      seconds = tracked_seconds.to_i
      return 0 if seconds <= 0
      return 1 if seconds < 2.hours
      return 2 if seconds < 4.hours
      return 3 if seconds < 8.hours
      return 4 if seconds < 12.hours

      5
    end

    def self.cache_key_for(user, date)
      d = normalize_month(date)
      tz = user.safe_settings.timezone.presence || 'UTC'
      plan_segment = user.plan_restricted? ? 'lite' : 'pro'
      ['timeline_month_summary', user.id, d.strftime('%Y-%m'), tz, plan_segment, 'v2']
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
        weeks: weeks,
        status_counts: status_counts
      }
    end

    # Visit counts for the displayed month, keyed by status string. Powers the
    # FILTER pills under the calendar so they reflect "this month" rather
    # than the user's lifetime totals.
    def status_counts
      @status_counts ||= @user.scoped_visits
                              .where(started_at: month_range)
                              .group(:status)
                              .count
                              .transform_keys { |k| visit_status_label(k) }
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

        # Track count is independent of duration — a track with NULL duration
        # still represents activity, so the day shouldn't bucket as 0/black.
        track_count.each do |date_str, count|
          result[date_str] ||= default_day
          result[date_str][:track_count] += count.to_i
        end

        result
      end
    end

    def default_day
      {
        tracked_seconds: 0,
        track_count: 0,
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
      @track_seconds ||= track_day_attributions[:seconds]
    end

    def track_count
      @track_count ||= track_day_attributions[:count]
    end

    # `seconds` is pro-rated across days a track spans (so the heat grid
    # reflects actual presence on each day). `count` stays start-day-only,
    # preserving the field's prior meaning of "tracks that began this day".
    def track_day_attributions
      @track_day_attributions ||= begin
        seconds = Hash.new(0.0)
        count = Hash.new(0)
        overlapping_tracks.find_each do |track|
          start_day = track.start_at.in_time_zone(tz).to_date.to_s
          count[start_day] += 1
          TrackDayShares.shares_for(track, tz).each do |day, fraction|
            seconds[day.to_s] += track.duration.to_f * fraction
          end
        end
        { seconds: seconds, count: count }
      end
    end

    def overlapping_tracks
      @user.scoped_tracks.where('start_at <= ? AND end_at >= ?', month_range.last, month_range.first)
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

      cells = dates.map { |d| build_cell(d) }

      # Heat is graded relative to the busiest day IN THIS MONTH so every
      # month renders with full color range. Days outside the month aren't
      # considered when computing the max, but they still get bucketed.
      in_month_max = cells.select { |c| c[:in_month] }
                          .map { |c| c[:tracked_seconds].to_i }
                          .max.to_i

      cells.each { |c| c[:heat_bucket] = compute_heat_bucket(c, in_month_max) }

      cells.each_slice(7).to_a
    end

    def build_cell(date)
      key = date.strftime('%Y-%m-%d')
      data = day_data[key] || default_day

      {
        date: key,
        in_month: date.month == @month_start.month,
        tracked_seconds: data[:tracked_seconds],
        track_count: data[:track_count],
        visit_count: data[:visit_count],
        suggested_count: data[:suggested_count],
        disabled: disabled_cell?(date)
      }
    end

    # Returns 0..HEAT_BUCKETS. Days with any activity (visits or tracks)
    # always get at least bucket 1 so they aren't drawn as "no activity"
    # black cells, even when their stored durations are NULL/zero.
    def compute_heat_bucket(cell, month_max)
      return 0 unless cell_has_activity?(cell)
      return 1 if month_max.to_i <= 0

      ratio = cell[:tracked_seconds].to_f / month_max
      bucket = (ratio * HEAT_BUCKETS).ceil
      bucket.clamp(1, HEAT_BUCKETS)
    end

    def cell_has_activity?(cell)
      cell[:tracked_seconds].to_i.positive? ||
        cell[:visit_count].to_i.positive? ||
        cell[:track_count].to_i.positive?
    end

    def disabled_cell?(date)
      return false unless @user.plan_restricted?

      cutoff = @user.data_window_start.to_date
      date < cutoff
    end
  end
end

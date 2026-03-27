# frozen_string_literal: true

module Residency
  class DayCounter
    THRESHOLD_DAYS = 183

    def initialize(user, year)
      @user = user
      @year = year.to_i
    end

    def call
      {
        year: year,
        available_years: available_years,
        counting_mode: 'any_presence',
        days_in_year: days_in_year,
        total_tracked_days: total_tracked_days,
        daily_countries: daily_countries,
        countries: build_countries
      }
    end

    private

    attr_reader :user, :year

    def build_countries
      countries = country_days.map do |country_name, dates|
        iso_a2, _iso_a3 = Countries::IsoCodeMapper.iso_codes_from_country_name(country_name)
        flag = iso_a2.present? ? Countries::IsoCodeMapper.country_flag(iso_a2) : nil
        days = dates.size
        periods = build_periods(dates.sort)

        {
          country_name: country_name,
          iso_a2: iso_a2,
          days: days,
          percentage: total_tracked_days.positive? ? (days.to_f / total_tracked_days * 100).round(1) : 0,
          year_percentage: (days.to_f / days_in_year * 100).round(1),
          flag: flag,
          periods: periods,
          threshold_warning: days >= THRESHOLD_DAYS
        }
      end

      countries.sort_by { |c| -c[:days] }
    end

    def build_periods(sorted_dates)
      return [] if sorted_dates.empty?

      periods = []
      period_start = sorted_dates.first
      prev_date = period_start

      sorted_dates[1..].each do |date|
        if date == prev_date + 1.day
          prev_date = date
        else
          periods << format_period(period_start, prev_date)
          period_start = date
          prev_date = date
        end
      end

      periods << format_period(period_start, prev_date)
      periods
    end

    def format_period(start_date, end_date)
      {
        start_date: start_date.to_s,
        end_date: end_date.to_s,
        consecutive_days: (end_date - start_date).to_i + 1
      }
    end

    # Returns { "Germany" => [Date, Date, ...], "France" => [...] }
    def country_days
      @country_days ||= begin
        rows = fetch_daily_country_data
        result = Hash.new { |h, k| h[k] = [] }

        rows.each do |row|
          result[row['country_name']] << row['point_date'].to_date
        end

        result
      end
    end

    def total_tracked_days
      @total_tracked_days ||= country_days.values.flatten.uniq.size
    end

    # Returns { "2025-01-01" => "Germany", "2025-01-02" => "France", ... }
    # For multi-country days, picks the country with the most points
    def daily_countries
      @daily_countries ||= begin
        rows = fetch_daily_country_counts
        by_date = Hash.new { |h, k| h[k] = [] }

        rows.each do |row|
          by_date[row['point_date'].to_s] << { country: row['country_name'], count: row['point_count'].to_i }
        end

        by_date.transform_values { |entries| entries.max_by { |e| e[:count] }[:country] }
      end
    end

    def fetch_daily_country_data
      start_of_year = Time.zone.local(year, 1, 1, 0, 0, 0)
      end_of_year = start_of_year.end_of_year

      sql = <<~SQL.squish
        SELECT DISTINCT
          DATE(to_timestamp(timestamp) AT TIME ZONE 'UTC') as point_date,
          country_name
        FROM points
        WHERE user_id = $1
          AND timestamp >= $2
          AND timestamp <= $3
          AND country_name IS NOT NULL
          AND country_name != ''
        ORDER BY point_date
      SQL

      ActiveRecord::Base.connection.exec_query(
        sql,
        'Residency::DayCounter',
        [user.id, start_of_year.to_i, end_of_year.to_i]
      ).to_a
    end

    def fetch_daily_country_counts
      start_of_year = Time.zone.local(year, 1, 1, 0, 0, 0)
      end_of_year = start_of_year.end_of_year

      sql = <<~SQL.squish
        SELECT
          DATE(to_timestamp(timestamp) AT TIME ZONE 'UTC') as point_date,
          country_name,
          COUNT(*) as point_count
        FROM points
        WHERE user_id = $1
          AND timestamp >= $2
          AND timestamp <= $3
          AND country_name IS NOT NULL
          AND country_name != ''
        GROUP BY point_date, country_name
        ORDER BY point_date
      SQL

      ActiveRecord::Base.connection.exec_query(
        sql,
        'Residency::DayCounter::DailyCounts',
        [user.id, start_of_year.to_i, end_of_year.to_i]
      ).to_a
    end

    def days_in_year
      @days_in_year ||= Date.new(year).leap? ? 366 : 365
    end

    def available_years
      user.stats.distinct.pluck(:year).sort
    end
  end
end

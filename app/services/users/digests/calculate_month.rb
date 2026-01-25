# frozen_string_literal: true

module Users
  module Digests
    class CalculateMonth
      MINUTES_PER_DAY = 1440

      def initialize(user_id, year, month)
        @user = ::User.find(user_id)
        @year = year.to_i
        @month = month.to_i
      end

      def call
        return nil if stat.blank?

        digest = Users::Digest.find_or_initialize_by(
          user: user, year: year, month: month, period_type: :monthly
        )

        digest.assign_attributes(
          distance: stat.distance,
          toponyms: stat.toponyms || [],
          monthly_distances: stat.daily_distance || {},
          time_spent_by_location: calculate_time_spent,
          first_time_visits: calculate_first_time_visits,
          year_over_year: calculate_mom_comparison,
          all_time_stats: calculate_all_time_stats,
          travel_patterns: calculate_travel_patterns
        )

        digest.save!
        digest
      end

      private

      attr_reader :user, :year, :month

      def stat
        @stat ||= user.stats.find_by(year: year, month: month)
      end

      def calculate_time_spent
        country_minutes = calculate_actual_country_minutes

        {
          'countries' => format_top_countries(country_minutes),
          'cities' => calculate_city_time_spent,
          'total_country_minutes' => country_minutes.values.sum
        }
      end

      def format_top_countries(country_minutes)
        country_minutes
          .sort_by { |_, minutes| -minutes }
          .first(10)
          .map { |name, minutes| { 'name' => name, 'minutes' => minutes } }
      end

      def calculate_actual_country_minutes
        points_by_date = group_points_by_date
        country_minutes = Hash.new(0)

        points_by_date.each_value do |day_points|
          countries_on_day = day_points.map(&:country_name).uniq

          if countries_on_day.size == 1
            # Single country day - assign full day
            country_minutes[countries_on_day.first] += MINUTES_PER_DAY
          else
            # Multi-country day - calculate proportional time
            calculate_proportional_time(day_points, country_minutes)
          end
        end

        country_minutes
      end

      def group_points_by_date
        points = fetch_month_points_with_country_ordered

        points.group_by do |point|
          Time.zone.at(point.timestamp).to_date
        end
      end

      def calculate_proportional_time(day_points, country_minutes)
        country_spans = Hash.new(0)
        points_by_country = day_points.group_by(&:country_name)

        points_by_country.each do |country, country_points|
          timestamps = country_points.map(&:timestamp)
          span_seconds = timestamps.max - timestamps.min
          # Minimum 60 seconds (1 min) for single-point countries
          country_spans[country] = [span_seconds, 60].max
        end

        total_spans = country_spans.values.sum.to_f

        country_spans.each do |country, span|
          proportional_minutes = (span / total_spans * MINUTES_PER_DAY).round
          country_minutes[country] += proportional_minutes
        end
      end

      def fetch_month_points_with_country_ordered
        start_timestamp, end_timestamp = TimezoneHelper.month_bounds(year, month, user_timezone)

        user.points
            .without_raw_data
            .where('timestamp >= ? AND timestamp <= ?', start_timestamp, end_timestamp)
            .where.not(country_name: [nil, ''])
            .select(:country_name, :timestamp)
            .order(timestamp: :asc)
      end

      def user_timezone
        user.timezone.presence || TimezoneHelper::DEFAULT_TIMEZONE
      end

      def calculate_city_time_spent
        city_time = aggregate_city_time_from_stat

        city_time
          .sort_by { |_, minutes| -minutes }
          .first(10)
          .map { |name, minutes| { 'name' => name, 'minutes' => minutes } }
      end

      def aggregate_city_time_from_stat
        city_time = Hash.new(0)

        toponyms = stat.toponyms
        return city_time unless toponyms.is_a?(Array)

        toponyms.each do |toponym|
          next unless toponym.is_a?(Hash)
          next unless toponym['cities'].is_a?(Array)

          toponym['cities'].each do |city|
            next unless city.is_a?(Hash)

            stayed_for = city['stayed_for'].to_i
            city_name = city['city']

            city_time[city_name] += stayed_for if city_name.present?
          end
        end

        city_time
      end

      def calculate_first_time_visits
        MonthlyFirstTimeVisitsCalculator.new(user, year, month).call
      end

      def calculate_mom_comparison
        MonthOverMonthCalculator.new(user, year, month).call
      end

      def calculate_all_time_stats
        {
          'total_countries' => user.countries_visited_uncached.size,
          'total_cities' => user.cities_visited_uncached.size,
          'total_distance' => user.stats.sum(:distance).to_s
        }
      end

      def calculate_travel_patterns
        {
          'time_of_day' => Stats::TimeOfDayQuery.new(user, year, month, user.timezone).call,
          'activity_breakdown' => ActivityBreakdownCalculator.new(user, year, month).call
        }
      end
    end
  end
end

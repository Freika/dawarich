# frozen_string_literal: true

module Users
  module Digests
    class CalculateYear
      MINUTES_PER_DAY = 1440

      def initialize(user_id, year)
        @user = ::User.find(user_id)
        @year = year.to_i
      end

      def call
        return nil if monthly_stats.empty?

        digest = Users::Digest.find_or_initialize_by(user: user, year: year, period_type: :yearly)

        digest.assign_attributes(
          distance: total_distance,
          toponyms: aggregate_toponyms,
          monthly_distances: build_monthly_distances,
          time_spent_by_location: calculate_time_spent,
          first_time_visits: calculate_first_time_visits,
          year_over_year: calculate_yoy_comparison,
          all_time_stats: calculate_all_time_stats,
          travel_patterns: calculate_travel_patterns
        )

        digest.save!
        digest
      end

      private

      attr_reader :user, :year

      def monthly_stats
        @monthly_stats ||= user.stats.where(year: year).order(:month)
      end

      def total_distance
        monthly_stats.sum(:distance)
      end

      def aggregate_toponyms
        country_cities = Hash.new { |h, k| h[k] = Set.new }

        monthly_stats.each do |stat|
          toponyms = stat.toponyms
          next unless toponyms.is_a?(Array)

          toponyms.each do |toponym|
            next unless toponym.is_a?(Hash)

            country = toponym['country']
            next if country.blank?

            if toponym['cities'].is_a?(Array)
              toponym['cities'].each do |city|
                city_name = city['city'] if city.is_a?(Hash)
                country_cities[country].add(city_name) if city_name.present?
              end
            else
              # Ensure country appears even if no cities
              country_cities[country]
            end
          end
        end

        country_cities.sort_by { |_country, cities| -cities.size }.map do |country, cities|
          {
            'country' => country,
            'cities' => cities.to_a.sort.map { |city| { 'city' => city } }
          }
        end
      end

      def build_monthly_distances
        result = {}

        monthly_stats.each do |stat|
          result[stat.month.to_s] = stat.distance.to_s
        end

        # Fill in missing months with 0
        (1..12).each do |month|
          result[month.to_s] ||= '0'
        end

        result
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
        # Use SQL aggregation to avoid loading millions of points into memory
        # Groups by date and country, returning min/max timestamps and country count per day
        daily_country_stats = fetch_daily_country_stats
        country_minutes = Hash.new(0)

        # Group by date to process multi-country days
        daily_country_stats.group_by { |row| row['point_date'] }.each do |_date, day_rows|
          if day_rows.size == 1
            # Single country day - assign full day
            country_minutes[day_rows.first['country_name']] += MINUTES_PER_DAY
          else
            # Multi-country day - calculate proportional time
            calculate_proportional_time_from_stats(day_rows, country_minutes)
          end
        end

        country_minutes
      end

      def fetch_daily_country_stats
        start_of_year = Time.zone.local(year, 1, 1, 0, 0, 0)
        end_of_year = start_of_year.end_of_year

        sql = <<~SQL
          SELECT
            DATE(to_timestamp(timestamp) AT TIME ZONE 'UTC') as point_date,
            country_name,
            MIN(timestamp) as min_timestamp,
            MAX(timestamp) as max_timestamp
          FROM points
          WHERE user_id = #{user.id}
            AND timestamp >= #{start_of_year.to_i}
            AND timestamp <= #{end_of_year.to_i}
            AND country_name IS NOT NULL
            AND country_name != ''
          GROUP BY point_date, country_name
          ORDER BY point_date, min_timestamp
        SQL

        ActiveRecord::Base.connection.execute(sql).to_a
      end

      def calculate_proportional_time_from_stats(day_rows, country_minutes)
        country_spans = {}

        day_rows.each do |row|
          span_seconds = row['max_timestamp'].to_i - row['min_timestamp'].to_i
          # Minimum 60 seconds (1 min) for single-point countries
          country_spans[row['country_name']] = [span_seconds, 60].max
        end

        total_spans = country_spans.values.sum.to_f

        country_spans.each do |country, span|
          proportional_minutes = (span / total_spans * MINUTES_PER_DAY).round
          country_minutes[country] += proportional_minutes
        end
      end

      def calculate_city_time_spent
        city_time = aggregate_city_time_from_monthly_stats

        city_time
          .sort_by { |_, minutes| -minutes }
          .first(10)
          .map { |name, minutes| { 'name' => name, 'minutes' => minutes } }
      end

      def aggregate_city_time_from_monthly_stats
        city_time = Hash.new(0)

        monthly_stats.each do |stat|
          process_stat_toponyms(stat, city_time)
        end

        city_time
      end

      def process_stat_toponyms(stat, city_time)
        toponyms = stat.toponyms
        return unless toponyms.is_a?(Array)

        toponyms.each do |toponym|
          process_toponym_cities(toponym, city_time)
        end
      end

      def process_toponym_cities(toponym, city_time)
        return unless toponym.is_a?(Hash)
        return unless toponym['cities'].is_a?(Array)

        toponym['cities'].each do |city|
          next unless city.is_a?(Hash)

          stayed_for = city['stayed_for'].to_i
          city_name = city['city']

          city_time[city_name] += stayed_for if city_name.present?
        end
      end

      def calculate_first_time_visits
        FirstTimeVisitsCalculator.new(user, year).call
      end

      def calculate_yoy_comparison
        YearOverYearCalculator.new(user, year).call
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
          'time_of_day' => Stats::TimeOfDayQuery.new(user, year, nil, user.timezone).call,
          'seasonality' => SeasonalityCalculator.new(user, year).call,
          'activity_breakdown' => ActivityBreakdownCalculator.new(user, year, nil).call
        }
      end
    end
  end
end

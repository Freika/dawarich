# frozen_string_literal: true

module Users
  module Digests
    class CalculateMonth
      def initialize(user_id, year, month)
        @user = ::User.find(user_id)
        @year = year.to_i
        @month = month.to_i
      end

      def call
        return nil if stat.blank?

        Time.use_zone(user.timezone || Time.zone.name) do
          digest = Users::Digest.find_or_initialize_by(
            user: user, year: year, month: month, period_type: :monthly
          )

          digest.assign_attributes(
            distance: stat.distance,
            toponyms: stat.toponyms || [],
            monthly_distances: (stat.daily_distance || []).to_h.transform_keys(&:to_s),
            time_spent_by_location: calculate_time_spent,
            first_time_visits: calculate_first_time_visits,
            year_over_year: calculate_mom_comparison,
            all_time_stats: calculate_all_time_stats,
            travel_patterns: calculate_travel_patterns
          )

          digest.save!
          digest
        end
      end

      private

      attr_reader :user, :year, :month

      def stat
        @stat ||= user.stats.find_by(year: year, month: month)
      end

      def calculate_time_spent
        country_minutes = CountryMinutesCalculator.new(fetch_month_points_with_country_ordered, Time.zone)

        {
          'countries' => country_minutes.top_countries,
          'cities' => calculate_city_time_spent,
          'total_country_minutes' => country_minutes.total_minutes
        }
      end

      def fetch_month_points_with_country_ordered
        start_of_month = Time.zone.local(year, month, 1, 0, 0, 0)
        end_of_month = start_of_month.end_of_month

        user.points
            .without_raw_data
            .where('timestamp >= ? AND timestamp <= ?', start_of_month.to_i, end_of_month.to_i)
            .where.not(country_name: [nil, ''])
            .select(:country_name, :timestamp)
            .order(timestamp: :asc)
      end

      def calculate_city_time_spent
        CityMinutesCalculator.new(stat.toponyms).call
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
          'total_distance' => user.scoped_stats.sum(:distance).to_s
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

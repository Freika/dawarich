# frozen_string_literal: true

module Users
  module Digests
    class CalculateWeek
      WIDENING = 2.days

      def initialize(user_id, start_date, end_date)
        @user = ::User.find(user_id)
        @start_date = start_date
        @end_date = end_date
      end

      def call
        Time.use_zone(user.timezone.presence || Time.zone.name) do
          digest = Users::Digest.find_or_initialize_by(
            user: user, year: local_end.cwyear, week: local_end.cweek, period_type: :weekly
          )

          digest.assign_attributes(
            month: nil,
            distance: distance,
            toponyms: toponyms,
            time_spent_by_location: time_spent_by_location
          )

          digest.save!
          digest
        end
      end

      private

      attr_reader :user, :start_date, :end_date

      def local_start
        @local_start ||= start_date.in_time_zone.to_date
      end

      def local_end
        @local_end ||= end_date.in_time_zone.to_date
      end

      def local_range
        local_start..local_end
      end

      def distance
        Stats::RangeDistanceQuery
          .new(widened_points, local_range, user.timezone_iana)
          .call
          .sum { |_, meters| meters }
      end

      def toponyms
        @toponyms ||= CountriesAndCities.new(
          points_in_range,
          min_minutes_spent_in_city: user.safe_settings.min_minutes_spent_in_city,
          max_gap_minutes: user.safe_settings.max_gap_minutes_in_city
        ).call.map { |country_data| serialize_country(country_data) }
      end

      def serialize_country(country_data)
        {
          'country' => country_data.country,
          'cities' => country_data.cities.map do |city|
            {
              'city' => city.city,
              'points' => city.points,
              'timestamp' => city.timestamp,
              'stayed_for' => city.stayed_for
            }
          end
        }
      end

      def time_spent_by_location
        country_minutes = CountryMinutesCalculator.new(points_with_country, Time.zone)

        {
          'countries' => country_minutes.top_countries,
          'cities' => CityMinutesCalculator.new(toponyms).call,
          'total_country_minutes' => country_minutes.total_minutes
        }
      end

      def widened_points
        @widened_points ||= user.points
                                .not_anomaly
                                .where(timestamp: widened_timestamps)
                                .select(:lonlat, :timestamp, :city, :country_name, :country_id, :velocity)
                                .order(timestamp: :asc)
      end

      def widened_timestamps
        start_at = (local_start.in_time_zone - WIDENING).to_i
        end_at = (local_end.in_time_zone.end_of_day + WIDENING).to_i

        start_at..end_at
      end

      def points_in_range
        @points_in_range ||= widened_points.where(
          '(to_timestamp(timestamp) AT TIME ZONE ?)::date BETWEEN ? AND ?',
          user.timezone_iana, local_start, local_end
        )
      end

      def points_with_country
        points_in_range.where.not(country_name: [nil, ''])
      end
    end
  end
end

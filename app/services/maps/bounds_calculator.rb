# frozen_string_literal: true

module Maps
  class BoundsCalculator
    class NoUserFoundError < StandardError; end
    class NoDateRangeError < StandardError; end

    def initialize(user:, start_date:, end_date:)
      @user = user
      @start_date = start_date
      @end_date = end_date
    end

    def call
      validate_inputs!

      start_timestamp = Maps::DateParameterCoercer.new(@start_date).call
      end_timestamp = Maps::DateParameterCoercer.new(@end_date).call

      points_relation = @user.points.where(timestamp: start_timestamp..end_timestamp)
      point_count = points_relation.count

      return build_no_data_response if point_count.zero?

      bounds_result = execute_bounds_query(start_timestamp, end_timestamp)
      build_success_response(bounds_result, point_count)
    end

    private

    def validate_inputs!
      raise NoUserFoundError, 'No user found' unless @user
      raise NoDateRangeError, 'No date range specified' unless @start_date && @end_date
    end

    def execute_bounds_query(start_timestamp, end_timestamp)
      ActiveRecord::Base.connection.exec_query(
        "SELECT MIN(latitude) as min_lat, MAX(latitude) as max_lat,
                MIN(longitude) as min_lng, MAX(longitude) as max_lng
         FROM points
         WHERE user_id = $1
         AND timestamp BETWEEN $2 AND $3",
        'bounds_query',
        [@user.id, start_timestamp, end_timestamp]
      ).first
    end

    def build_success_response(bounds_result, point_count)
      {
        success: true,
        data: {
          min_lat: bounds_result['min_lat'].to_f,
          max_lat: bounds_result['max_lat'].to_f,
          min_lng: bounds_result['min_lng'].to_f,
          max_lng: bounds_result['max_lng'].to_f,
          point_count: point_count
        }
      }
    end

    def build_no_data_response
      {
        success: false,
        error: 'No data found for the specified date range',
        point_count: 0
      }
    end
  end
end

# frozen_string_literal: true

class Digests::Queries::Overview
  def initialize(user, date_range)
    @user = user
    @date_range = date_range
    @start_timestamp = date_range.begin.to_i
    @end_timestamp = date_range.end.to_i
  end

  def call
    {
      countries_count: count_countries,
      cities_count: count_cities,
      places_count: count_places,
      points_count: count_points
    }
  end

  private

  def count_countries
    @user.points
         .where(timestamp: @start_timestamp..@end_timestamp)
         .where.not(country_name: nil)
         .distinct
         .count(:country_name)
  end

  def count_cities
    @user.points
         .where(timestamp: @start_timestamp..@end_timestamp)
         .where.not(city: nil)
         .distinct
         .count(:city)
  end

  def count_places
    @user.visits
         .joins(:area)
         .where(started_at: @date_range)
         .distinct
         .count('areas.id')
  end

  def count_points
    @user.points
         .where(timestamp: @start_timestamp..@end_timestamp)
         .count
  end
end

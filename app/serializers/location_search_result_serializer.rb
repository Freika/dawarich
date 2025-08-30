# frozen_string_literal: true

class LocationSearchResultSerializer
  def initialize(search_result)
    @search_result = search_result
  end

  def call
    {
      query: @search_result[:query],
      locations: serialize_locations(@search_result[:locations]),
      total_locations: @search_result[:total_locations],
      search_metadata: @search_result[:search_metadata]
    }
  end

  private

  def serialize_locations(locations)
    locations.map do |location|
      {
        place_name: location[:place_name],
        coordinates: location[:coordinates],
        address: location[:address],
        total_visits: location[:total_visits],
        first_visit: location[:first_visit],
        last_visit: location[:last_visit],
        visits: serialize_visits(location[:visits])
      }
    end
  end

  def serialize_visits(visits)
    visits.map do |visit|
      {
        timestamp: visit[:timestamp],
        date: visit[:date],
        coordinates: visit[:coordinates],
        distance_meters: visit[:distance_meters],
        duration_estimate: visit[:duration_estimate],
        points_count: visit[:points_count],
        accuracy_meters: visit[:accuracy_meters],
        visit_details: visit[:visit_details]
      }
    end
  end
end
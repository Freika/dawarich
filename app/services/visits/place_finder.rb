# frozen_string_literal: true

module Visits
  # Finds or creates places for visits
  class PlaceFinder
    attr_reader :user

    SEARCH_RADIUS = 500 # meters
    SIMILARITY_RADIUS = 50 # meters

    def initialize(user)
      @user = user
    end

    def find_or_create_place(visit_data)
      lat = visit_data[:center_lat].round(5)
      lon = visit_data[:center_lon].round(5)

      # First check if there's an existing place
      existing_place = find_existing_place(lat, lon, visit_data[:suggested_name])

      # If we found an exact match, return it
      if existing_place
        return {
          main_place: existing_place,
          suggested_places: find_suggested_places(lat, lon, existing_place.id)
        }
      end

      # Get potential places from all sources
      potential_places = collect_potential_places(visit_data)

      # Find or create the main place
      main_place = select_or_create_main_place(potential_places, lat, lon, visit_data[:suggested_name])

      # Get suggested places including our main place
      all_suggested_places = potential_places.presence || [main_place]

      {
        main_place: main_place,
        suggested_places: all_suggested_places.uniq { |place| place.name }
      }
    end

    private

    # Step 1: Find existing place
    def find_existing_place(lat, lon, name)
      # Try to find existing place by location first
      existing_by_location = Place.near([lat, lon], SIMILARITY_RADIUS, :m).first
      return existing_by_location if existing_by_location

      # Then try by name if available
      return nil unless name.present?

      Place.where(name: name)
           .near([lat, lon], SEARCH_RADIUS, :m)
           .first
    end

    # Step 2: Collect potential places from all sources
    def collect_potential_places(visit_data)
      lat = visit_data[:center_lat].round(5)
      lon = visit_data[:center_lon].round(5)

      # Get places from points' geodata
      places_from_points = extract_places_from_points(visit_data[:points], lat, lon)

      # Get places from external API
      places_from_api = fetch_places_from_api(lat, lon)

      # Combine and deduplicate by name
      combined_places = []

      # Add API places first (usually better quality)
      places_from_api.each do |api_place|
        combined_places << api_place unless place_name_exists?(combined_places, api_place.name)
      end

      # Add places from points if name doesn't already exist
      places_from_points.each do |point_place|
        combined_places << point_place unless place_name_exists?(combined_places, point_place.name)
      end

      combined_places
    end

    # Step 3: Extract places from points
    def extract_places_from_points(points, center_lat, center_lon)
      return [] if points.blank?

      # Filter points with geodata
      points_with_geodata = points.select { |point| point.geodata.present? }
      return [] if points_with_geodata.empty?

      # Process each point to create or find places
      places = []

      points_with_geodata.each do |point|
        place = create_place_from_point(point)
        places << place if place
      end

      places.uniq { |place| place.name }
    end

    # Step 4: Create place from point
    def create_place_from_point(point)
      return nil unless point.geodata.is_a?(Hash)

      properties = point.geodata['properties'] || {}
      return nil if properties.blank?

      # Get or build a name
      name = build_place_name(properties)
      return nil if name == Place::DEFAULT_NAME

      # Look for existing place with this name
      existing = Place.where(name: name)
                      .near([point.latitude, point.longitude], SIMILARITY_RADIUS, :m)
                      .first

      return existing if existing

      # Create new place
      place = Place.new(
        name: name,
        lonlat: "POINT(#{point.longitude} #{point.latitude})",
        latitude: point.latitude,
        longitude: point.longitude,
        city: properties['city'],
        country: properties['country'],
        geodata: point.geodata,
        source: :photon
      )

      place.save!
      place
    rescue ActiveRecord::RecordInvalid
      nil
    end

    # Step 5: Fetch places from API
    def fetch_places_from_api(lat, lon)
      # Get broader search results from Geocoder
      geocoder_results = Geocoder.search([lat, lon], radius: (SEARCH_RADIUS / 1000.0), units: :km)
      return [] if geocoder_results.blank?

      places = []

      geocoder_results.each do |result|
        place = create_place_from_api_result(result)
        places << place if place
      end

      places
    end

    # Step 6: Create place from API result
    def create_place_from_api_result(result)
      return nil unless result && result.data.is_a?(Hash)

      properties = result.data['properties'] || {}
      return nil if properties.blank?

      # Get or build a name
      name = build_place_name(properties)
      return nil if name == Place::DEFAULT_NAME

      # Look for existing place with this name
      existing = Place.where(name: name)
                      .near([result.latitude, result.longitude], SIMILARITY_RADIUS, :m)
                      .first

      return existing if existing

      # Create new place
      place = Place.new(
        name: name,
        lonlat: "POINT(#{result.longitude} #{result.latitude})",
        latitude: result.latitude,
        longitude: result.longitude,
        city: properties['city'],
        country: properties['country'],
        geodata: result.data,
        source: :photon
      )

      place.save!
      place
    rescue ActiveRecord::RecordInvalid
      nil
    end

    # Step 7: Select or create main place
    def select_or_create_main_place(potential_places, lat, lon, suggested_name)
      return create_default_place(lat, lon, suggested_name) if potential_places.blank?

      # Choose the closest place as the main one
      sorted_places = potential_places.sort_by do |place|
        place.distance_to([lat, lon], :m)
      end

      sorted_places.first
    end

    # Step 8: Create default place when no other options
    def create_default_place(lat, lon, suggested_name)
      name = suggested_name.presence || Place::DEFAULT_NAME

      place = Place.new(
        name: name,
        lonlat: "POINT(#{lon} #{lat})",
        latitude: lat,
        longitude: lon,
        source: :manual
      )

      place.save!
      place
    end

    # Step 9: Find suggested places
    def find_suggested_places(lat, lon, exclude_id = nil)
      query = Place.near([lat, lon], SEARCH_RADIUS, :m).with_distance([lat, lon], :m)
      query = query.where.not(id: exclude_id) if exclude_id
      query.limit(5)
    end

    # Helper methods

    def build_place_name(properties)
      name_components = [
        properties['name'],
        properties['street'],
        properties['housenumber'],
        properties['postcode'],
        properties['city']
      ].compact.reject(&:empty?).uniq

      name_components.any? ? name_components.join(', ') : Place::DEFAULT_NAME
    end

    def place_name_exists?(places, name)
      places.any? { |place| place.name == name }
    end
  end
end

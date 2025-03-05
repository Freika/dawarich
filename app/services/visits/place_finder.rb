# frozen_string_literal: true

module Visits
  # Finds or creates places for visits
  class PlaceFinder
    attr_reader :user

    def initialize(user)
      @user = user
    end

    def find_or_create_place(visit_data)
      lat = visit_data[:center_lat].round(5)
      lon = visit_data[:center_lon].round(5)
      name = visit_data[:suggested_name]

      # Define the search radius in meters
      search_radius = 100 # Adjust this value as needed

      # First check by exact coordinates
      existing_place = Place.where('ST_DWithin(lonlat, ST_SetSRID(ST_MakePoint(?, ?), 4326), 1)', lon, lat).first

      # If no exact match, check by name within radius
      existing_place ||= Place.where(name: name)
                              .where('ST_DWithin(lonlat, ST_SetSRID(ST_MakePoint(?, ?), 4326), ?)', lon, lat, search_radius)
                              .first

      return existing_place if existing_place

      # Use a database transaction with a lock to prevent race conditions
      Place.transaction do
        # Check again within transaction to prevent race conditions
        existing_place = Place.where('ST_DWithin(lonlat, ST_SetSRID(ST_MakePoint(?, ?), 4326), 50)', lon, lat)
                              .lock(true)
                              .first

        return existing_place if existing_place

        create_new_place(lat, lon, visit_data[:suggested_name])
      end
    end

    private

    def create_new_place(lat, lon, suggested_name)
      # If no existing place is found, create a new one
      place = Place.new(
        lonlat: "POINT(#{lon} #{lat})",
        latitude: lat,
        longitude: lon
      )

      # Get reverse geocoding data
      geocoded_data = Geocoder.search([lat, lon])

      if geocoded_data.present?
        first_result = geocoded_data.first
        data = first_result.data.with_indifferent_access
        properties = data['properties'] || {}

        # Build a descriptive name from available components
        name_components = [
          properties['name'],
          properties['street'],
          properties['housenumber'],
          properties['postcode'],
          properties['city']
        ].compact.uniq

        place.name = name_components.any? ? name_components.join(', ') : Place::DEFAULT_NAME
        place.city = properties['city']
        place.country = properties['country']
        place.geodata = data
        place.source = :photon

        place.save!

        # Process nearby organizations outside the main transaction
        process_nearby_organizations(geocoded_data.drop(1))
      else
        place.name = suggested_name || Place::DEFAULT_NAME
        place.source = :manual
        place.save!
      end

      place
    end

    def process_nearby_organizations(geocoded_data)
      # Fetch nearby organizations
      nearby_organizations = fetch_nearby_organizations(geocoded_data)

      # Save each organization as a possible place
      nearby_organizations.each do |org|
        lon = org[:longitude]
        lat = org[:latitude]

        # Check if a similar place already exists
        existing = Place.where(name: org[:name])
                        .where('ST_DWithin(lonlat, ST_SetSRID(ST_MakePoint(?, ?), 4326), 1)', lon, lat)
                        .first

        next if existing

        Place.create!(
          name: org[:name],
          lonlat: "POINT(#{lon} #{lat})",
          latitude: lat,
          longitude: lon,
          city: org[:city],
          country: org[:country],
          geodata: org[:geodata],
          source: :photon
        )
      end
    end

    def fetch_nearby_organizations(geocoded_data)
      geocoded_data.map do |result|
        data = result.data
        properties = data['properties'] || {}

        {
          name: properties['name'] || 'Unknown Organization',
          latitude: result.latitude,
          longitude: result.longitude,
          city: properties['city'],
          country: properties['country'],
          geodata: data
        }
      end
    end
  end
end

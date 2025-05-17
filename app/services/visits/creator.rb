# frozen_string_literal: true

module Visits
  # Creates visit records from detected visit data
  class Creator
    attr_reader :user

    def initialize(user)
      @user = user
    end

    def create_visits(visits)
      visits.map do |visit_data|
        # Check for existing confirmed visits at this location
        existing_confirmed = find_existing_confirmed_visit(visit_data)
        next existing_confirmed if existing_confirmed

        # Variables to store data outside the transaction
        visit_instance = nil
        place_data = nil

        # First transaction to create the visit
        ActiveRecord::Base.transaction do
          # Try to find matching area or place
          area = find_matching_area(visit_data)

          # Only find/create place if no area was found
          place_data = PlaceFinder.new(user).find_or_create_place(visit_data) unless area

          main_place = place_data&.dig(:main_place)

          visit_instance = Visit.create!(
            user: user,
            area: area,
            place: main_place,
            started_at: Time.zone.at(visit_data[:start_time]),
            ended_at: Time.zone.at(visit_data[:end_time]),
            duration: visit_data[:duration] / 60, # Convert to minutes
            name: generate_visit_name(area, main_place, visit_data[:suggested_name]),
            status: :suggested
          )

          Point.where(id: visit_data[:points].map(&:id)).update_all(visit_id: visit_instance.id)
        end

        # Associate suggested places outside the main transaction
        # to avoid deadlocks when multiple processes run simultaneously
        if place_data&.dig(:suggested_places).present?
          associate_suggested_places(visit_instance, place_data[:suggested_places])
        end

        visit_instance
      end.compact
    end

    private

    # Find if there's already a confirmed visit at this location within a similar time
    def find_existing_confirmed_visit(visit_data)
      # Define time window to look for existing visits (slightly wider than the visit)
      start_time = Time.zone.at(visit_data[:start_time]) - 1.hour
      end_time = Time.zone.at(visit_data[:end_time]) + 1.hour

      # Look for confirmed visits with a similar location
      user.visits
          .confirmed
          .where('(started_at BETWEEN ? AND ?) OR (ended_at BETWEEN ? AND ?)',
                 start_time, end_time, start_time, end_time)
          .find_each do |visit|
        # Skip if the visit doesn't have place or area coordinates
        next unless visit.place || visit.area

        # Get coordinates to compare
        visit_lat = visit.place&.lat || visit.area&.latitude
        visit_lon = visit.place&.lon || visit.area&.longitude

        next unless visit_lat && visit_lon

        # Calculate distance between centers
        distance = Geocoder::Calculations.distance_between(
          [visit_data[:center_lat], visit_data[:center_lon]],
          [visit_lat, visit_lon],
          units: :km
        )

        # If this confirmed visit is within 100 meters of the new suggestion
        return visit if distance <= 0.1
      end

      nil
    end

    # Create place_visits records directly to avoid deadlocks
    def associate_suggested_places(visit, suggested_places)
      existing_place_ids = visit.place_visits.pluck(:place_id)

      # Only create associations that don't already exist
      place_ids_to_add = suggested_places.map(&:id) - existing_place_ids

      # Skip if there's nothing to add
      return if place_ids_to_add.empty?

      # Batch create place_visit records
      place_visits_attrs = place_ids_to_add.map do |place_id|
        { visit_id: visit.id, place_id: place_id, created_at: Time.current, updated_at: Time.current }
      end

      # Use insert_all for efficient bulk insertion without callbacks
      PlaceVisit.insert_all(place_visits_attrs) if place_visits_attrs.any?
    end

    def find_matching_area(visit_data)
      user.areas.find do |area|
        near_area?([visit_data[:center_lat], visit_data[:center_lon]], area)
      end
    end

    def near_area?(center, area)
      distance = Geocoder::Calculations.distance_between(
        center,
        [area.latitude, area.longitude],
        units: :km
      )
      distance * 1000 <= area.radius # Convert to meters
    end

    def generate_visit_name(area, place, suggested_name)
      return area.name if area
      return place.name if place
      return suggested_name if suggested_name.present?

      'Unknown Location'
    end
  end
end

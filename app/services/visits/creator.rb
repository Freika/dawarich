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
        ActiveRecord::Base.transaction do
          # Try to find matching area or place
          area = find_matching_area(visit_data)
          place = area ? nil : PlaceFinder.new(user).find_or_create_place(visit_data)

          visit = Visit.create!(
            user: user,
            area: area,
            place: place,
            started_at: Time.zone.at(visit_data[:start_time]),
            ended_at: Time.zone.at(visit_data[:end_time]),
            duration: visit_data[:duration] / 60, # Convert to minutes
            name: generate_visit_name(area, place, visit_data[:suggested_name]),
            status: :suggested
          )

          Point.where(id: visit_data[:points].map(&:id)).update_all(visit_id: visit.id)

          visit
        end
      end
    end

    private

    def find_matching_area(visit_data)
      user.areas.find do |area|
        near_area?([visit_data[:center_lat], visit_data[:center_lon]], area)
      end
    end

    def near_area?(center, area)
      distance = Geocoder::Calculations.distance_between(
        center,
        [area.latitude, area.longitude]
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

# frozen_string_literal: true

module Visits
  # Creates visit records from detected visit data
  class Creator
    attr_reader :user

    def initialize(user, scoring_on: false)
      @user = user
      @scoring_on = scoring_on
    end

    def create_visits(visits)
      visits.map do |visit_data|
        existing_visit = find_existing_visit(visit_data)
        next nil if existing_visit

        ActiveRecord::Base.transaction do
          area = find_matching_area(visit_data)
          main_place = area ? nil : PlaceFinder.new(user).find_or_create_place(visit_data)

          visit_instance = Visit.create!(
            {
              user: user, area: area, place: main_place,
              started_at: Time.zone.at(visit_data[:start_time]),
              ended_at:   Time.zone.at(visit_data[:end_time]),
              duration:   visit_data[:duration] / 60,
              name:       generate_visit_name(area, main_place, visit_data[:suggested_name]),
              status:     :suggested
            }.merge(confidence_attributes(visit_data, area, main_place))
          )

          Point.where(id: visit_data[:points].map(&:id)).update_all(visit_id: visit_instance.id)
          visit_instance
        end
      end.compact
    end

    private

    def confidence_attributes(visit_data, area, main_place)
      return {} unless @scoring_on

      result = Visits::ConfidenceScorer.new(
        duration_seconds:   visit_data[:end_time] - visit_data[:start_time],
        point_count:        visit_data[:points].size,
        accuracies:         visit_data[:points].map(&:accuracy),
        radius_meters:      visit_data[:radius],
        stay_radius_meters: stay_radius_meters,
        min_points:         min_points_setting,
        place_match:        place_match_kind(area, main_place)
      ).call

      { confidence: result[:score], confidence_breakdown: result[:breakdown] }
    end

    # Constant per job run — read once and memoize instead of per visit in the loop.
    def stay_radius_meters
      @stay_radius_meters ||= user.safe_settings.visit_radius_meters
    end

    def min_points_setting
      @min_points_setting ||= user.safe_settings.visit_min_points
    end

    def place_match_kind(area, main_place)
      return :area if area
      return :place if main_place && main_place.name != Place::DEFAULT_NAME

      nil
    end

    # Find if there's already a confirmed/suggested/declined visit at this location within a similar time
    def find_existing_visit(visit_data)
      confirmed = confirmed_visit_owning_points(visit_data)
      return confirmed if confirmed

      # Define time window to look for existing visits (slightly wider than the visit)
      start_time = Time.zone.at(visit_data[:start_time]) - 1.hour
      end_time = Time.zone.at(visit_data[:end_time]) + 1.hour

      # Look for visits with a similar location
      user.visits
          .where(
            'started_at <= :end AND ended_at >= :start',
            start: start_time, end: end_time
          )
          .find_each do |visit|
        visit_lat, visit_lon = visit.center
        next unless visit_lat && visit_lon

        # Calculate distance between centers
        distance = Geocoder::Calculations.distance_between(
          [visit_data[:center_lat], visit_data[:center_lon]],
          [visit_lat, visit_lon],
          units: :km
        )

        # If this visit is within 100 meters of the new suggestion
        return visit if distance <= 0.1
      end

      nil
    end

    def confirmed_visit_owning_points(visit_data)
      visit_ids = Array(visit_data[:points]).filter_map(&:visit_id).uniq
      return nil if visit_ids.empty?

      user.visits.confirmed.find_by(id: visit_ids)
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

# frozen_string_literal: true

module Places
  # Re-evaluates machine-owned visits affected by a Place being created or
  # reshaped. Confirmed and declined visits are deliberately outside this
  # service: their Place association belongs to the user.
  class ReattributeSuggestedVisits
    def initialize(user:, changed_place:)
      @user = user
      @changed_place = changed_place
    end

    def call
      centers = centers_for(candidate_visit_ids)
      return 0 if centers.empty?

      places = user.places.select(:id, :name, :lonlat, :visit_radius).to_a
      changed_at = []

      user.visits.machine_detected.where(id: centers.keys).includes(:place).find_each do |visit|
        winner = containing_place(places, centers.fetch(visit.id))
        attributes = attributes_for(visit, winner)
        next if attributes.empty?

        visit.update_columns(attributes)
        changed_at << visit.started_at
      end

      Visits::Detection::MachineVisitWipe.bust_month_caches(user, changed_at)
      changed_at.size
    end

    private

    attr_reader :user, :changed_place

    # A create can claim previously unplaced visits in its new radius. A
    # reshape must additionally reconsider every Suggested Visit currently
    # attached to the changed Place so stale associations can be removed.
    def candidate_visit_ids
      assigned_ids = user.visits.machine_detected.where(place_id: changed_place.id).pluck(:id)
      (assigned_ids + visit_ids_inside_changed_place).uniq
    end

    def visit_ids_inside_changed_place
      Point.where(visit_id: user.visits.machine_detected.select(:id))
           .group(:visit_id)
           .having(centroid_inside_sql, changed_place.lon, changed_place.lat, changed_place.visit_radius)
           .pluck(:visit_id)
    end

    def centroid_inside_sql
      <<~SQL.squish
        ST_DWithin(
          ST_SetSRID(
            ST_MakePoint(
              AVG(ST_X(points.lonlat::geometry)),
              AVG(ST_Y(points.lonlat::geometry))
            ),
            4326
          )::geography,
          ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography,
          ?
        )
      SQL
    end

    def centers_for(visit_ids)
      return {} if visit_ids.empty?

      Point.where(visit_id: visit_ids)
           .group(:visit_id)
           .pluck(
             :visit_id,
             Arel.sql('AVG(ST_Y(lonlat::geometry))'),
             Arel.sql('AVG(ST_X(lonlat::geometry))')
           )
           .to_h { |visit_id, lat, lon| [visit_id, [lat.to_f, lon.to_f]] }
    end

    def containing_place(places, center)
      candidates = places.filter_map do |place|
        distance = distance_meters(center, [place.lat, place.lon])
        [place, distance] if distance <= place.visit_radius
      end

      candidates.min_by { |place, distance| [place.visit_radius, distance, place.id] }&.first
    end

    def attributes_for(visit, winner)
      attributes = {}
      attributes[:place_id] = winner&.id if visit.place_id != winner&.id

      label = winner&.name
      label = nil if winner.nil? && visit.location_label == visit.place&.name
      attributes[:location_label] = label if label != visit.location_label
      attributes
    end

    def distance_meters(first, second)
      Geocoder::Calculations.distance_between(first, second, units: :km) * 1000
    end
  end
end

# frozen_string_literal: true

module Places
  # Re-evaluates machine-owned visits affected by a Place being created or
  # reshaped. Confirmed and declined visits are deliberately outside this
  # service: their Place association belongs to the user.
  class ReattributeSuggestedVisits
    MAX_STAY_SPREAD_METERS = 2_000

    def initialize(user:, changed_place:)
      @user = user
      @changed_place = changed_place
    end

    def call
      centers = Visit.weighted_centers(candidate_visit_ids)
      return 0 if centers.empty?

      search_radius = user.places.maximum(:visit_radius).to_i
      changed_at = []

      user.visits.machine_detected.where(id: centers.keys).includes(:place).find_each do |visit|
        winner = user.places.attribution_for(*centers.fetch(visit.id), search_radius:)
        attributes = attributes_for(visit, winner)
        next if attributes.empty?
        next if Visit.machine_detected.where(id: visit.id).update_all(attributes).zero?

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
      nearby_visit_ids = Point.where(user_id: user.id, visit_id: user.visits.machine_detected.select(:id))
                              .where('ST_DWithin(points.lonlat, ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography, ?)',
                                     changed_place.lon, changed_place.lat,
                                     changed_place.visit_radius + MAX_STAY_SPREAD_METERS)
                              .select(:visit_id)

      Point.where(visit_id: nearby_visit_ids)
           .group(:visit_id)
           .having(centroid_inside_sql, changed_place.lon, changed_place.lat, changed_place.visit_radius)
           .pluck(:visit_id)
    end

    def centroid_inside_sql
      <<~SQL.squish
        ST_DWithin(
          ST_SetSRID(
            ST_MakePoint(#{Visit::CENTER_LONGITUDE_SQL}, #{Visit::CENTER_LATITUDE_SQL}),
            4326
          )::geography,
          ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography,
          ?
        )
      SQL
    end

    def attributes_for(visit, winner)
      attributes = {}
      attributes[:place_id] = winner&.id if visit.place_id != winner&.id

      label = winner&.name
      label = nil if winner.nil? && visit.location_label == visit.place&.name
      attributes[:location_label] = label if label != visit.location_label
      attributes
    end
  end
end

# frozen_string_literal: true

# Labels EXISTING visits with a newly created or reshaped area, so drawing an
# area still reveals its history immediately — the behavior the retired
# nightly area detector provided by rescanning raw points. This pass touches
# only visit rows (place coords or point centroid), never re-detects, and is
# purely additive: visits already attributed to an area keep it.
class Areas::RelabelVisitsJob < ApplicationJob
  queue_as :visit_suggesting
  sidekiq_options retry: 1

  def perform(area_id)
    area = Area.find_by(id: area_id)
    return unless area

    labeled_at = []
    candidate_visits(area).find_in_batches(batch_size: 500) do |batch|
      centers = centers_for(batch)
      batch.each do |visit|
        next unless inside?(area, centers[visit.id])

        visit.update_columns(label_attributes(area, visit))
        labeled_at << visit.started_at
      end
    end

    Visits::Detection::MachineVisitWipe.bust_month_caches(area.user, labeled_at)
    Rails.logger.info("[Areas::RelabelVisitsJob] area_id=#{area.id} labeled=#{labeled_at.size}")
  end

  private

  def candidate_visits(area)
    area.user.visits.active.where(area_id: nil).includes(:place)
  end

  # Machine visits take the area's name, matching what detection itself does
  # for area-attributed stays; anything user-owned keeps its name.
  def label_attributes(area, visit)
    attrs = { area_id: area.id }
    attrs[:name] = area.name if visit.status == 'suggested' && visit.detection_version.present? && area.name.present?
    attrs
  end

  # Place coords come preloaded; the point-backed rest resolves through one
  # grouped centroid query instead of a per-visit Visit#center point load.
  def centers_for(visits)
    with_place, point_backed = visits.partition(&:place)
    centers = with_place.to_h { |visit| [visit.id, [visit.place.lat, visit.place.lon]] }
    return centers if point_backed.empty?

    Point.where(visit_id: point_backed.map(&:id))
         .group(:visit_id)
         .pluck(:visit_id, Arel.sql('AVG(ST_Y(lonlat::geometry))'), Arel.sql('AVG(ST_X(lonlat::geometry))'))
         .each { |visit_id, lat, lon| centers[visit_id] = [lat, lon] }

    centers
  end

  def inside?(area, center)
    return false if center.nil?

    lat, lon = center
    return false if lat.blank? || (lat.zero? && lon.zero?)

    distance_m = Geocoder::Calculations.distance_between(
      [lat, lon], [area.latitude, area.longitude], units: :km
    ) * 1000

    distance_m <= area.radius
  end
end

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

    labeled = 0
    candidate_visits(area).find_each do |visit|
      next unless inside?(area, visit.center)

      visit.update_columns(area_id: area.id)
      labeled += 1
    end

    Rails.logger.info("[Areas::RelabelVisitsJob] area_id=#{area.id} labeled=#{labeled}")
  end

  private

  def candidate_visits(area)
    area.user.visits.active.where(area_id: nil).includes(:place)
  end

  def inside?(area, center)
    lat, lon = center
    return false if lat.blank? || (lat.zero? && lon.zero?)

    distance_m = Geocoder::Calculations.distance_between(
      [lat, lon], [area.latitude, area.longitude], units: :km
    ) * 1000

    distance_m <= area.radius
  end
end

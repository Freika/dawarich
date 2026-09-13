# frozen_string_literal: true

# Compatibility wrapper for jobs enqueued by direct legacy Area writes.
# It materializes the canonical Place and forwards attribution to the Place
# workflow without creating any new Visit#area_id associations.
class Areas::RelabelVisitsJob < ApplicationJob
  queue_as :visit_suggesting
  sidekiq_options retry: 1

  def perform(area_id)
    area = Area.find_by(id: area_id)
    return unless area

    place = Places::LegacyAreaAdapter.new(user: area.user).resolve(area)
    count = Places::ReattributeSuggestedVisits.new(user: area.user, changed_place: place).call

    Rails.logger.info("[Areas::RelabelVisitsJob] area_id=#{area.id} place_id=#{place.id} reattributed=#{count}")
  end
end

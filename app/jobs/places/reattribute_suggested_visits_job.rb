# frozen_string_literal: true

class Places::ReattributeSuggestedVisitsJob < ApplicationJob
  queue_as :visit_suggesting
  sidekiq_options retry: 1

  def perform(user_id, place_id)
    user = User.find_by(id: user_id)
    place = user&.places&.find_by(id: place_id)
    return unless place

    count = Places::ReattributeSuggestedVisits.new(user: user, changed_place: place).call
    Rails.logger.info("[#{self.class}] place_id=#{place.id} reattributed=#{count}")
  end
end

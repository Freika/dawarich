# frozen_string_literal: true

class PlaceVisitsCalculatingJob < ApplicationJob
  queue_as :visit_suggesting
  sidekiq_options retry: false

  def perform(user_id)
    user = find_user_or_skip(user_id) || return

    return unless user.safe_settings.visits_suggestions_enabled?

    # Only user-owned places (with user_id)
    Places::Visits::Create.new(user, user.places).call
  end
end

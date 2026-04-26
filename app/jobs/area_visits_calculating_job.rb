# frozen_string_literal: true

class AreaVisitsCalculatingJob < ApplicationJob
  include UserTimezone

  queue_as :visit_suggesting
  sidekiq_options retry: false

  def perform(user_id)
    user = find_user_or_skip(user_id) || return

    return unless user.safe_settings.visits_suggestions_enabled?

    with_user_timezone(user) do
      Areas::Visits::Create.new(user, user.areas).call
    end
  end
end

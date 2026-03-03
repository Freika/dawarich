# frozen_string_literal: true

class AreaVisitsCalculatingJob < ApplicationJob
  include UserTimezone

  queue_as :visit_suggesting
  sidekiq_options retry: false

  def perform(user_id)
    user = find_user_or_skip(user_id) || return

    with_user_timezone(user) do
      areas = user.areas
      Areas::Visits::Create.new(user, areas).call
    end
  end
end

# frozen_string_literal: true

class AreaVisitsCalculatingJob < ApplicationJob
  include UserTimezone

  queue_as :visit_suggesting
  sidekiq_options retry: false

  def perform(user_id)
    user = User.find(user_id)

    with_user_timezone(user) do
      areas = user.areas
      Areas::Visits::Create.new(user, areas).call
    end
  end
end

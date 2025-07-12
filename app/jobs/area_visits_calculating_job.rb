# frozen_string_literal: true

class AreaVisitsCalculatingJob < ApplicationJob
  queue_as :visit_suggesting
  sidekiq_options retry: false

  def perform(user_id)
    user = User.find(user_id)
    areas = user.areas

    Areas::Visits::Create.new(user, areas).call
  end
end

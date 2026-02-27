# frozen_string_literal: true

class AreaVisitsCalculatingJob < ApplicationJob
  include UserTimezone

  queue_as :visit_suggesting
  sidekiq_options retry: false

  def perform(user_id)
    user = User.find_by(id: user_id)
    unless user
      Rails.logger.info "#{self.class.name}: User #{user_id} not found, skipping"
      return
    end

    with_user_timezone(user) do
      areas = user.areas
      Areas::Visits::Create.new(user, areas).call
    end
  end
end

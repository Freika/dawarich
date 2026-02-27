# frozen_string_literal: true

class Users::ExportDataJob < ApplicationJob
  queue_as :exports

  sidekiq_options retry: false

  def perform(user_id)
    user = User.find_by(id: user_id)
    unless user
      Rails.logger.info "#{self.class.name}: User #{user_id} not found, skipping"
      return
    end

    Users::ExportData.new(user).export
  end
end

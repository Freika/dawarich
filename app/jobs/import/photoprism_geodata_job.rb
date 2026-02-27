# frozen_string_literal: true

class Import::PhotoprismGeodataJob < ApplicationJob
  queue_as :imports
  sidekiq_options retry: false

  def perform(user_id)
    user = User.find_by(id: user_id)
    unless user
      Rails.logger.info "#{self.class.name}: User #{user_id} not found, skipping"
      return
    end

    Photoprism::ImportGeodata.new(user).call
  end
end

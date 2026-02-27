# frozen_string_literal: true

class Import::ImmichGeodataJob < ApplicationJob
  queue_as :imports

  def perform(user_id)
    user = User.find_by(id: user_id)
    unless user
      Rails.logger.info "#{self.class.name}: User #{user_id} not found, skipping"
      return
    end

    Immich::ImportGeodata.new(user).call
  end
end

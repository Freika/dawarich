# frozen_string_literal: true

class Import::ImmichGeodataJob < ApplicationJob
  queue_as :imports
  sidekiq_options retry: false

  def perform(user_id)
    user = User.find(user_id)

    Immich::ImportGeodata.new(user).call
  end
end

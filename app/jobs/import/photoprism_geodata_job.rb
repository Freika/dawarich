# frozen_string_literal: true

class Import::PhotoprismGeodataJob < ApplicationJob
  queue_as :imports
  sidekiq_options retry: false

  def perform(user_id)
    user = User.find(user_id)

    Photoprism::ImportGeodata.new(user).call
  end
end

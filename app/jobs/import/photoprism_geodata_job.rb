# frozen_string_literal: true

class Import::PhotoprismGeodataJob < ApplicationJob
  queue_as :imports
  sidekiq_options retry: false

  def perform(user_id)
    user = find_non_deleted_user(user_id)
    return unless user

    Photoprism::ImportGeodata.new(user).call
  end
end

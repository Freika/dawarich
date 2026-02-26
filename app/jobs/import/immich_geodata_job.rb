# frozen_string_literal: true

class Import::ImmichGeodataJob < ApplicationJob
  queue_as :imports

  def perform(user_id)
    user = find_non_deleted_user(user_id)
    return unless user

    Immich::ImportGeodata.new(user).call
  end
end

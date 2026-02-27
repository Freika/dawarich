# frozen_string_literal: true

class Import::ImmichGeodataJob < ApplicationJob
  queue_as :imports

  def perform(user_id)
    user = find_user_or_skip(user_id) || return

    Immich::ImportGeodata.new(user).call
  end
end

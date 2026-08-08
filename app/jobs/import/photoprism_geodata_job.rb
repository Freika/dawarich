# frozen_string_literal: true

class Import::PhotoprismGeodataJob < ApplicationJob
  queue_as :imports
  sidekiq_options retry: false
  retry_on(*Photos::ConnectionErrors::RETRYABLE, wait: :polynomially_longer, attempts: 5)

  def perform(user_id)
    user = find_user_or_skip(user_id) || return

    Photoprism::ImportGeodata.new(user).call
  end
end

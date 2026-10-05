# frozen_string_literal: true

class Import::PhotoprismGeodataJob < ApplicationJob
  queue_as :imports
  sidekiq_options retry: false
  retry_on(*Photos::ConnectionErrors::RETRYABLE, wait: :polynomially_longer, attempts: 5) do |_job, error|
    ExceptionReporter.call(error, 'Photoprism geodata import gave up after repeated connection failures')
  end

  def perform(user_id)
    user = find_user_or_skip(user_id) || return
    zone = Time.zone.name
    result = PhoenixLease.try_hold("photoprism-geodata:#{user.id}") do
      Imports::IntegrationCommands.legacy('imports.photoprism_geodata') do
        Photoprism::ImportGeodata.new(user).call
      end
    end
    return result unless [false, :not_owner].include?(result)

    Imports::IntegrationCommands.forward('photoprism', user.id, event_id: job_id, time_zone: zone)
  end
end

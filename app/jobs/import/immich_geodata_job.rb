# frozen_string_literal: true

class Import::ImmichGeodataJob < ApplicationJob
  queue_as :imports
  retry_on(*Photos::ConnectionErrors::RETRYABLE, wait: :polynomially_longer, attempts: 5) do |_job, error|
    ExceptionReporter.call(error, 'Immich geodata import gave up after repeated connection failures')
  end

  def perform(user_id)
    user = find_user_or_skip(user_id) || return
    zone = Time.zone.name
    result = PhoenixLease.try_hold("immich-geodata:#{user.id}") do
      Imports::IntegrationCommands.legacy('imports.immich_geodata') do
        Immich::ImportGeodata.new(user).call
      end
    end
    return result unless [false, :not_owner].include?(result)

    Imports::IntegrationCommands.forward('immich', user.id, event_id: job_id, time_zone: zone)
  end
end

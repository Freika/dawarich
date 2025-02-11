# frozen_string_literal: true

class TelemetrySendingJob < ApplicationJob
  queue_as :default

  def perform
    return unless ENV['ENABLE_TELEMETRY'] == 'true'

    data = Telemetry::Gather.new.call
    Rails.logger.info("Telemetry data: #{data}")

    Telemetry::Send.new(data).call
  end
end

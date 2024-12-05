# frozen_string_literal: true

class TelemetrySendingJob < ApplicationJob
  queue_as :default

  def perform
    return if ENV['DISABLE_TELEMETRY'] == 'true'

    data = Telemetry::Gather.new.call

    Telemetry::Send.new(data).call
  end
end

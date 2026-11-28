# frozen_string_literal: true

# Dawarich Cloud's product analytics. The browser script and server-side
# events share the site, so both read it from here.
module Rybbit
  HOST = ENV.fetch('RYBBIT_HOST', 'https://rybbit.dwri.xyz')
  SITE_ID = ENV.fetch('RYBBIT_SITE_ID', '87c1f532b59f')

  class DeliveryError < StandardError; end

  # Sends one custom event through the track API. RYBBIT_API_KEY marks the
  # request as trusted server-side ingestion.
  def self.track(event_name:, properties:, pathname:)
    headers = { 'Content-Type' => 'application/json' }
    headers['Authorization'] = "Bearer #{ENV['RYBBIT_API_KEY']}" if ENV['RYBBIT_API_KEY'].present?

    response = HTTParty.post(
      "#{HOST}/api/track",
      headers:, timeout: 10,
      body: { site_id: SITE_ID, type: 'custom_event', event_name:, pathname:, properties: properties.to_json }.to_json
    )
    raise DeliveryError, "Rybbit answered #{response.code} for #{event_name}" unless response.success?

    # A 200 can still mean "not stored" (bot filter, plan limit); retrying
    # would not change that, so it is only logged.
    return if stored?(response)

    Rails.logger.warn("[Rybbit] #{event_name} not tracked: #{response.body.to_s.truncate(200)}")
  end

  def self.stored?(response)
    body = JSON.parse(response.body.to_s)
    body.is_a?(Hash) && body['success'] == true && body['message'].nil?
  rescue JSON::ParserError
    false
  end
  private_class_method :stored?
end

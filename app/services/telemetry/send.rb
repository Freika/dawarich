# frozen_string_literal: true

class Telemetry::Send
  BUCKET = 'dawarich_metrics'
  ORG = 'monitoring'

  def initialize(payload)
    @payload = payload
  end

  def call
    return unless ENV['ENABLE_TELEMETRY'] == 'true'

    line_protocol = build_line_protocol
    response = send_request(line_protocol)
    handle_response(response)
  end

  private

  attr_reader :payload

  def build_line_protocol
    tag_string = payload[:tags].map { |k, v| "#{k}=#{v}" }.join(',')
    field_string = payload[:fields].map { |k, v| "#{k}=#{v}" }.join(',')

    "#{payload[:measurement]},#{tag_string} #{field_string} #{payload[:timestamp].to_i}"
  end

  def send_request(line_protocol)
    HTTParty.post(
      "#{TELEMETRY_URL}?org=#{ORG}&bucket=#{BUCKET}&precision=s",
      body: line_protocol,
      headers: {
        'Authorization' => "Token #{Base64.decode64(TELEMETRY_STRING)}",
        'Content-Type' => 'text/plain'
      }
    )
  end

  def handle_response(response)
    Rails.logger.error("InfluxDB write failed: #{response.body}") unless response.success?

    response
  end
end

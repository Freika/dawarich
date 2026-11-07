# frozen_string_literal: true

require 'net/http'

class ProductAnalyticsErasureJob < ApplicationJob
  queue_as :default

  def perform(distinct_id, pass: 1)
    return if distinct_id.blank?
    if ENV['PRODUCT_POSTHOG_PERSONAL_API_KEY'].blank? || ENV['PRODUCT_POSTHOG_PROJECT_ID'].blank?
      raise 'PostHog erasure is not configured'
    end

    host = ENV.fetch('PRODUCT_POSTHOG_APP_HOST', 'https://eu.posthog.com')
    uri = URI.join(host, "/api/projects/#{ENV.fetch('PRODUCT_POSTHOG_PROJECT_ID')}/persons/bulk_delete/")
    request = Net::HTTP::Post.new(uri)
    request['Authorization'] = "Bearer #{ENV.fetch('PRODUCT_POSTHOG_PERSONAL_API_KEY')}"
    request['Content-Type'] = 'application/json'
    request.body = { distinct_ids: [distinct_id], delete_events: true, delete_recordings: true }.to_json
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', open_timeout: 5,
read_timeout: 15) do |http|
      http.request(request)
    end
    raise "PostHog erasure failed (HTTP #{response.code})" unless response.code.to_i == 202

    # The SDK may still have a pre-revocation event queued for delivery. The
    # second pass catches events that arrived after the first delete request.
    self.class.set(wait: 24.hours).perform_later(distinct_id, pass: 2) if pass == 1
  end
end

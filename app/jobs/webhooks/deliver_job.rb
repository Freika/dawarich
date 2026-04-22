# frozen_string_literal: true

require 'net/http'

module Webhooks
  class DeliverJob < ApplicationJob
    queue_as :webhooks

    CIRCUIT_BREAKER_THRESHOLD = 5
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 10

    retry_on Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED, SocketError,
             wait: :polynomially_longer, attempts: 5
    discard_on ActiveJob::DeserializationError

    class DeliveryError < StandardError; end

    def perform(delivery_id)
      delivery = WebhookDelivery.find_by(id: delivery_id)
      return unless delivery

      webhook = delivery.webhook
      return unless webhook

      delivery.increment!(:attempt_count)

      if Webhooks::UrlValidator.call(webhook.url) != :ok
        record_failure(delivery, webhook, status: nil, body: nil, error: 'URL failed revalidation (possible DNS rebinding)')
        webhook.update!(active: false)
        return
      end

      body = Webhooks::PayloadBuilder.call(delivery.geofence_event).to_json
      signature = Webhooks::Signer.sign(body: body, secret: webhook.secret)

      response = post(
        url: webhook.url,
        body: body,
        signature: signature,
        delivery_id: delivery.id,
        event_type: delivery.geofence_event.event_type
      )

      if response.is_a?(Net::HTTPSuccess)
        record_success(delivery, webhook, response)
      else
        record_failure(delivery, webhook, status: response.code.to_i, body: response.body)
        raise DeliveryError, "HTTP #{response.code}"
      end
    rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED, SocketError => e
      record_failure(delivery, webhook, status: nil, body: nil, error: e.message) if delivery && webhook
      raise
    end

    private

    def post(url:, body:, signature:, delivery_id:, event_type:)
      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == 'https')
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = READ_TIMEOUT

      request = Net::HTTP::Post.new(uri.request_uri)
      request['Content-Type'] = 'application/json'
      request['User-Agent'] = user_agent
      request['X-Dawarich-Event'] = "geofence.#{event_type}"
      request['X-Dawarich-Delivery'] = delivery_id.to_s
      request['X-Dawarich-Signature'] = signature
      request.body = body

      http.request(request)
    end

    def user_agent
      version = Rails.application.config.try(:dawarich_version) || 'dev'
      "Dawarich/#{version}"
    end

    def record_success(delivery, webhook, response)
      delivery.update!(
        status: :success,
        response_status: response.code.to_i,
        response_body: response.body&.to_s&.truncate(1024),
        delivered_at: Time.current
      )
      webhook.update!(
        last_delivery_at: Time.current,
        last_success_at: Time.current,
        consecutive_failures: 0
      )
    end

    def record_failure(delivery, webhook, status:, body:, error: nil)
      delivery.update!(
        status: :failure,
        response_status: status,
        response_body: body&.to_s&.truncate(1024),
        error_message: error
      )
      webhook.increment!(:consecutive_failures)
      webhook.update!(last_delivery_at: Time.current)
      return unless webhook.consecutive_failures >= CIRCUIT_BREAKER_THRESHOLD

      webhook.update!(active: false)
    end
  end
end

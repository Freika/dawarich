# frozen_string_literal: true

require 'net/http'

module Webhooks
  class DeliverJob < ApplicationJob
    queue_as :webhooks
    sidekiq_options retry: false

    ATTEMPTS = 5
    BREAKER_THRESHOLD = 5
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 10
    BODY_LIMIT = 1024
    TRANSPORT_ERRORS = [
      Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, IOError,
      OpenSSL::SSL::SSLError, Timeout::Error
    ].freeze

    class DeliveryError < StandardError; end

    retry_on DeliveryError, attempts: ATTEMPTS, wait: :polynomially_longer do |job, error|
      job.send(:record_final_failure, error.message)
    end
    discard_on ActiveJob::DeserializationError

    def perform(delivery_id)
      @delivery = WebhookDelivery.includes(:webhook, geofence_event: :area).find_by(id: delivery_id)
      return unless @delivery

      @delivery.increment!(:attempt_count)
      response = post(webhook.resolved_url_ip!)
      return record_success(response) if response.is_a?(Net::HTTPSuccess)

      record_attempt(status: response.code.to_i, body: response.body, error: "HTTP #{response.code}")
      raise DeliveryError, "HTTP #{response.code}"
    rescue UrlValidatable::BlockedUrlError => e
      record_attempt(status: nil, body: nil, error: e.message)
      record_final_failure(e.message, deactivate: true)
    rescue *TRANSPORT_ERRORS => e
      record_attempt(status: nil, body: nil, error: e.message)
      raise DeliveryError, e.message
    end

    private

    def webhook
      @delivery.webhook
    end

    def post(ip_address)
      uri = URI.parse(webhook.url)
      http = Net::HTTP.new(uri.hostname, uri.port, nil)
      http.ipaddr = ip_address
      http.use_ssl = uri.scheme == 'https'
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = READ_TIMEOUT
      http.start { |connection| connection.request(build_request(uri)) }
    end

    def build_request(uri)
      body = PayloadBuilder.call(@delivery.geofence_event).to_json
      Net::HTTP::Post.new(uri.request_uri).tap do |request|
        request['Content-Type'] = 'application/json'
        request['User-Agent'] = "Dawarich/#{APP_VERSION}"
        request['X-Dawarich-Event'] = "geofence.#{@delivery.geofence_event.event_type}"
        request['X-Dawarich-Delivery'] = @delivery.id.to_s
        request['X-Dawarich-Signature'] = Signer.sign(body:, secret: webhook.secret)
        request.body = body
      end
    end

    def record_success(response)
      now = Time.current
      @delivery.update!(status: :success, response_status: response.code.to_i, response_body: truncate(response.body),
                        error_message: nil, delivered_at: now)
      webhook.update!(last_delivery_at: now, last_success_at: now, consecutive_failures: 0)
    end

    def record_attempt(status:, body:, error:)
      @delivery.update!(status: :retrying, response_status: status, response_body: truncate(body), error_message: error)
    end

    def record_final_failure(message, deactivate: false)
      delivery = @delivery || WebhookDelivery.find_by(id: arguments.first)
      return unless delivery

      delivery.update!(status: :failure, error_message: message)
      hook = delivery.webhook
      hook.update!(last_delivery_at: Time.current, consecutive_failures: hook.consecutive_failures + 1)
      trip_breaker(hook) if deactivate || hook.consecutive_failures >= BREAKER_THRESHOLD
    end

    def trip_breaker(hook)
      hook.update!(active: false)
      Notifications::Create.new(
        user: hook.user, kind: :warning, deduplicate: true,
        title: I18n.t('webhooks.notifications.deactivated.title', locale: hook.user.locale),
        content: I18n.t('webhooks.notifications.deactivated.content', name: hook.name,
                                                                      locale: hook.user.locale)
      ).call
    end

    def truncate(body)
      body&.to_s&.truncate(BODY_LIMIT)
    end
  end
end

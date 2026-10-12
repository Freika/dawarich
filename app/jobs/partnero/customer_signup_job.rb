# frozen_string_literal: true

# Registers a referred signup with Partnero so the affiliate is credited when the
# Paddle transaction lands later.
#
# This runs server-side rather than as a po('customers','signup') call in the
# browser because reverse-trial signups redirect straight to manager.dawarich.app
# for checkout — those users never load another page on this host, so a JS call
# would never fire for them.
class Partnero::CustomerSignupJob < ApplicationJob
  class AttributionFailed < StandardError; end

  queue_as :highest_priority

  API_URL = 'https://api.partnero.com/v1/customers'
  HTTP_TIMEOUT_SECONDS = 10
  # The customer is keyed by user id, so a replay of an already-registered signup
  # is the desired end state rather than an error worth retrying.
  ALREADY_REGISTERED = 409

  retry_on Net::OpenTimeout, wait: :polynomially_longer, attempts: 5
  retry_on Net::ReadTimeout, wait: :polynomially_longer, attempts: 5
  retry_on HTTParty::Error, wait: :polynomially_longer, attempts: 5
  retry_on SocketError, wait: :polynomially_longer, attempts: 5
  retry_on Errno::ECONNREFUSED, wait: :polynomially_longer, attempts: 5
  retry_on AttributionFailed, wait: :polynomially_longer, attempts: 5

  def perform(user_id, partner_key)
    return if ENV['PARTNERO_API_KEY'].blank? || partner_key.blank?

    user = find_user_or_skip(user_id) || return

    response = HTTParty.post(
      API_URL,
      headers: headers,
      body: body_for(user, partner_key),
      timeout: HTTP_TIMEOUT_SECONDS
    )

    return if response.success? || response.code == ALREADY_REGISTERED

    raise AttributionFailed, "Partnero rejected the signup (HTTP #{response.code})"
  rescue StandardError => e
    message = e.is_a?(AttributionFailed) ? e.message : "Partnero signup attribution failed (#{e.class.name})"
    reported_error = StandardError.new(message)
    reported_error.set_backtrace(e.backtrace)
    ExceptionReporter.call(reported_error, 'Partnero signup attribution failed')
    error = e.is_a?(Net::ReadTimeout) ? e.class.new.exception(message) : e.exception(message)
    error.set_backtrace(e.backtrace)
    raise error, cause: nil
  end

  private

  def headers
    {
      'Authorization' => "Bearer #{ENV.fetch('PARTNERO_API_KEY')}",
      'Content-Type' => 'application/json',
      'Accept' => 'application/json'
    }
  end

  def body_for(user, partner_key)
    {
      partner: { key: partner_key },
      key: user.id.to_s,
      email: user.email,
      name: user.first_name,
      surname: user.last_name
    }.to_json
  end
end

# frozen_string_literal: true

class Users::CreationWebhookJob < ApplicationJob
  queue_as :highest_priority

  class WebhookDeliveryError < StandardError; end

  HTTP_TIMEOUT_SECONDS = 10

  retry_on Net::OpenTimeout, wait: :polynomially_longer, attempts: 5
  retry_on Net::ReadTimeout, wait: :polynomially_longer, attempts: 5
  retry_on HTTParty::Error, wait: :polynomially_longer, attempts: 5
  retry_on SocketError, wait: :polynomially_longer, attempts: 5
  retry_on Errno::ECONNREFUSED, wait: :polynomially_longer, attempts: 5

  def perform(user_id)
    return if ENV['MANAGER_URL'].blank?

    user = find_user_or_skip(user_id) || return

    payload = {
      user_id: user.id,
      email: user.email,
      first_name: user.first_name,
      last_name: user.last_name,
      active_until: user.active_until,
      status: user.status,
      action: 'create_user'
    }

    token = Subscription::EncodeJwtToken.new(payload, ENV['JWT_SECRET_KEY']).call

    request_url = "#{ENV['MANAGER_URL']}/api/v1/users"
    headers = {
      'Content-Type' => 'application/json',
      'Accept' => 'application/json'
    }

    response = HTTParty.post(
      request_url,
      headers: headers,
      body: { token: token }.to_json,
      timeout: HTTP_TIMEOUT_SECONDS
    )

    return if response.success?

    raise WebhookDeliveryError,
          "Manager rejected user creation webhook (user_id=#{user.id}, status=#{response.code})"
  rescue StandardError => e
    ExceptionReporter.call(e, "Failed to notify Manager of user creation (user_id=#{user_id})")
    raise
  end
end

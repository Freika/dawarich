# frozen_string_literal: true

class Users::DestructionWebhookJob < ApplicationJob
  queue_as :highest_priority

  HTTP_TIMEOUT_SECONDS = 10

  retry_on Net::OpenTimeout, wait: :polynomially_longer, attempts: 5
  retry_on Net::ReadTimeout, wait: :polynomially_longer, attempts: 5
  retry_on HTTParty::Error, wait: :polynomially_longer, attempts: 5
  retry_on SocketError, wait: :polynomially_longer, attempts: 5
  retry_on Errno::ECONNREFUSED, wait: :polynomially_longer, attempts: 5

  def perform(user_id, email)
    return if ENV['MANAGER_URL'].blank?

    payload = {
      user_id: user_id,
      email: email,
      action: 'destroy_user'
    }

    token = Subscription::EncodeJwtToken.new(payload, ENV['JWT_SECRET_KEY']).call

    request_url = "#{ENV['MANAGER_URL']}/api/v1/users/unlink"
    headers = {
      'Content-Type' => 'application/json',
      'Accept' => 'application/json'
    }

    HTTParty.post(
      request_url,
      headers: headers,
      body: { token: token }.to_json,
      timeout: HTTP_TIMEOUT_SECONDS
    )
  rescue StandardError => e
    ExceptionReporter.call(e, "Failed to notify Manager of user destruction (user_id=#{user_id})")
    raise
  end
end

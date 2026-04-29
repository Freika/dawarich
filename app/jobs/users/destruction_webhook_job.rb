# frozen_string_literal: true

class Users::DestructionWebhookJob < ApplicationJob
  queue_as :default

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

    HTTParty.post(request_url, headers: headers, body: { token: token }.to_json)
  end
end

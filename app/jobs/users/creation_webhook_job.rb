# frozen_string_literal: true

class Users::CreationWebhookJob < ApplicationJob
  queue_as :highest_priority

  def perform(user_id)
    return if ENV['MANAGER_URL'].blank?

    user = find_user_or_skip(user_id) || return

    payload = {
      user_id: user.id,
      email: user.email,
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

    HTTParty.post(request_url, headers: headers, body: { token: token }.to_json)
  end
end

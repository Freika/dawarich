# frozen_string_literal: true

class Users::TrialWebhookJob < ApplicationJob
  queue_as :default

  def perform(user_id)
    user = User.find(user_id)

    token = Subscription::EncodeJwtToken.new(
      { user_id: user.id, email: user.email, action: 'create_user' },
      ENV['JWT_SECRET_KEY']
    ).call

    request_url = "#{ENV['MANAGER_URL']}/api/v1/users"
    headers = {
      'Content-Type' => 'application/json',
      'Accept' => 'application/json'
    }

    HTTParty.post(request_url, headers: headers, body: { token: token }.to_json)
  end
end

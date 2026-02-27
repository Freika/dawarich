# frozen_string_literal: true

class Users::TrialWebhookJob < ApplicationJob
  queue_as :default

  def perform(user_id)
    user = User.find_by(id: user_id)
    unless user
      Rails.logger.info "#{self.class.name}: User #{user_id} not found, skipping"
      return
    end

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

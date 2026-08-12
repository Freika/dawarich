# frozen_string_literal: true

# Registers a referred signup with Partnero so the affiliate is credited when the
# Paddle transaction lands later.
#
# This runs server-side rather than as a po('customers','signup') call in the
# browser because reverse-trial signups redirect straight to manager.dawarich.app
# for checkout — those users never load another page on this host, so a JS call
# would never fire for them.
class Partnero::CustomerSignupJob < ApplicationJob
  queue_as :highest_priority

  API_URL = 'https://api.partnero.com/v1/customers'

  def perform(user_id, partner_key)
    return if ENV['PARTNERO_API_KEY'].blank? || partner_key.blank?

    user = User.find_by(id: user_id)
    return if user.nil?

    HTTParty.post(API_URL, headers: headers, body: body_for(user, partner_key))
  rescue StandardError => e
    # A lost commission must never break the signup it belongs to.
    ExceptionReporter.call(e, 'Partnero signup attribution failed')
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

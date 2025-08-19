# frozen_string_literal: true

class Subscription::EncodeJwtToken
  def initialize(payload, secret_key)
    @payload = payload
    @secret_key = secret_key
  end

  def call
    JWT.encode(
      @payload,
      @secret_key,
      'HS256'
    )
  end
end

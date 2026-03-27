# frozen_string_literal: true

class Subscription::DecodeJwtToken
  def initialize(token)
    @token = token
  end

  def call
    JWT.decode(
      @token,
      ENV.fetch('JWT_SECRET_KEY'),
      true,
      { algorithm: 'HS256' }
    ).first.symbolize_keys
  end
end

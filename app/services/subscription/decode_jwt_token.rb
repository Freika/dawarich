# frozen_string_literal: true

class Subscription::DecodeJwtToken
  class InvalidPurpose < JWT::DecodeError; end

  def initialize(token, expected_purpose: nil)
    @token = token
    @expected_purpose = expected_purpose
  end

  def call
    decoded = JWT.decode(
      @token,
      ENV.fetch('JWT_SECRET_KEY'),
      true,
      { algorithm: 'HS256', required_claims: ['exp'], verify_expiration: true }
    ).first.symbolize_keys

    if @expected_purpose && decoded[:purpose].to_s != @expected_purpose.to_s
      raise InvalidPurpose, "expected purpose=#{@expected_purpose}, got #{decoded[:purpose].inspect}"
    end

    decoded
  end
end

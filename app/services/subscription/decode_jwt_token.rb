# frozen_string_literal: true

class Subscription::DecodeJwtToken
  def initialize(token)
    @token = token
  end

  # Merges multiple visits into one
  # @return [Visit, nil] The merged visit or nil if merge failed
  def call
    JWT.decode(
      token,
      ENV['JWT_SECRET_KEY'],
      true,
      { algorithm: 'HS256' }
    ).first.symbolize_keys
  end
end

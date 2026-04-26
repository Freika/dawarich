# frozen_string_literal: true

class Subscription::DecodeJwtToken
  # Raised when an `expected_purpose:` argument is provided and the token's
  # `purpose` claim doesn't match. Inherits from `JWT::DecodeError` so the
  # existing `rescue JWT::DecodeError` blocks in calling controllers catch
  # purpose mismatches the same way they catch signature/expiry failures —
  # neither leaks information to the client beyond "link invalid".
  class InvalidPurpose < JWT::DecodeError; end

  # @param token [String] the encoded JWT
  # @param expected_purpose [String, nil] when set, the decoded `purpose`
  #   claim must match exactly. Pass nil only for the manager → dawarich
  #   callback path, which uses a different claim shape (event_id,
  #   event_timestamp_ms, etc.) and doesn't carry `purpose`.
  def initialize(token, expected_purpose: nil)
    @token = token
    @expected_purpose = expected_purpose
  end

  def call
    decoded = JWT.decode(
      @token,
      ENV.fetch('JWT_SECRET_KEY'),
      true,
      { algorithm: 'HS256' }
    ).first.symbolize_keys

    if @expected_purpose && decoded[:purpose].to_s != @expected_purpose.to_s
      raise InvalidPurpose, "expected purpose=#{@expected_purpose}, got #{decoded[:purpose].inspect}"
    end

    decoded
  end
end

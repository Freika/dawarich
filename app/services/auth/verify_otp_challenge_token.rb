# frozen_string_literal: true

module Auth
  class VerifyOtpChallengeToken
    class InvalidToken < StandardError; end

    def initialize(token)
      @token = token
    end

    def call
      raise InvalidToken, 'blank token' if @token.blank?

      decoded, = JWT.decode(@token, ENV.fetch('JWT_SECRET_KEY'), true, algorithm: 'HS256')
      raise InvalidToken, 'wrong purpose' unless decoded['purpose'] == 'otp_challenge'

      user = User.find_by(id: decoded['user_id'])
      raise InvalidToken, 'user not found' unless user

      user
    rescue JWT::DecodeError => e
      raise InvalidToken, e.message
    end
  end
end

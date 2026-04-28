# frozen_string_literal: true

module Auth
  class VerifyGoogleToken
    class InvalidToken < StandardError; end

    def initialize(id_token)
      @id_token = id_token
    end

    def call
      raise InvalidToken, 'blank token' if @id_token.blank?

      client_ids = [ENV['GOOGLE_IOS_CLIENT_ID'], ENV['GOOGLE_ANDROID_CLIENT_ID']].compact
      raise InvalidToken, 'Google client IDs not configured' if client_ids.empty?

      claims = GoogleIDToken::Validator.new.check(@id_token, client_ids)
      raise InvalidToken, 'validator returned nil' if claims.nil?

      claims.symbolize_keys
    rescue GoogleIDToken::ValidationError => e
      raise InvalidToken, e.message
    end
  end
end

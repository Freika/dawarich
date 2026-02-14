# frozen_string_literal: true

module GooglePhotos
  class RefreshToken
    GOOGLE_TOKEN_URL = 'https://oauth2.googleapis.com/token'

    attr_reader :user

    def initialize(user)
      @user = user
    end

    def call
      return { success: false, error: 'No refresh token available' } unless refresh_token_present?
      return { success: true, access_token: current_access_token } unless token_expired?

      refresh_access_token
    end

    private

    def refresh_token_present?
      user.safe_settings.google_photos_refresh_token.present?
    end

    def current_access_token
      user.safe_settings.google_photos_access_token
    end

    def token_expired?
      expires_at = user.safe_settings.google_photos_token_expires_at
      return true if expires_at.blank?

      # Refresh if token expires within 5 minutes
      Time.current.to_i >= (expires_at.to_i - 300)
    end

    def refresh_access_token
      response = HTTParty.post(
        GOOGLE_TOKEN_URL,
        body: {
          client_id: ENV['GOOGLE_OAUTH_CLIENT_ID'],
          client_secret: ENV['GOOGLE_OAUTH_CLIENT_SECRET'],
          refresh_token: user.safe_settings.google_photos_refresh_token,
          grant_type: 'refresh_token'
        },
        headers: { 'Content-Type' => 'application/x-www-form-urlencoded' },
        timeout: 10
      )

      if response.success?
        save_new_tokens(response)
      else
        handle_refresh_error(response)
      end
    rescue HTTParty::Error, Net::OpenTimeout, Net::ReadTimeout => e
      Rails.logger.error("Google Photos token refresh error: #{e.message}")
      { success: false, error: e.message }
    end

    def save_new_tokens(response)
      parsed = JSON.parse(response.body)
      expires_at = Time.current.to_i + parsed['expires_in'].to_i

      existing_settings = user.settings || {}
      updated_settings = existing_settings.merge(
        'google_photos_access_token' => parsed['access_token'],
        'google_photos_token_expires_at' => expires_at
      )

      user.update!(settings: updated_settings)

      { success: true, access_token: parsed['access_token'] }
    rescue JSON::ParserError, ActiveRecord::RecordInvalid => e
      Rails.logger.error("Google Photos token save error: #{e.message}")
      { success: false, error: 'Failed to save new tokens' }
    end

    def handle_refresh_error(response)
      Rails.logger.error("Google Photos token refresh failed: #{response.code} - #{response.body}")

      # If refresh token is invalid, clear all tokens
      if response.code == 400 || response.code == 401
        clear_tokens
        { success: false, error: 'Refresh token invalid. Please reconnect Google Photos.' }
      else
        { success: false, error: 'Token refresh failed' }
      end
    end

    def clear_tokens
      existing_settings = user.settings || {}
      updated_settings = existing_settings.merge(
        'google_photos_access_token' => nil,
        'google_photos_refresh_token' => nil,
        'google_photos_token_expires_at' => nil
      )

      user.update(settings: updated_settings)
    end
  end
end

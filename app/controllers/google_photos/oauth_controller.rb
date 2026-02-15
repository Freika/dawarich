# frozen_string_literal: true

class GooglePhotos::OauthController < ApplicationController
  before_action :authenticate_user!
  before_action :check_google_photos_available

  GOOGLE_OAUTH_URL = 'https://accounts.google.com/o/oauth2/v2/auth'
  GOOGLE_TOKEN_URL = 'https://oauth2.googleapis.com/token'
  PHOTOS_SCOPE = 'https://www.googleapis.com/auth/photoslibrary.readonly'

  def authorize
    state = SecureRandom.hex(16)
    session[:google_photos_oauth_state] = state

    redirect_to authorization_url(state), allow_other_host: true
  end

  def callback
    if params[:error].present?
      return redirect_to settings_integrations_path,
                         alert: "Google Photos authorization failed: #{params[:error_description] || params[:error]}"
    end

    unless valid_state?
      return redirect_to settings_integrations_path, alert: 'Invalid OAuth state'
    end

    result = exchange_code_for_tokens
    if result[:success]
      save_tokens(result)
      redirect_to settings_integrations_path, notice: 'Google Photos connected successfully'
    else
      redirect_to settings_integrations_path, alert: "Failed to connect Google Photos: #{result[:error]}"
    end
  end

  def disconnect
    existing_settings = current_user.settings || {}
    updated_settings = existing_settings.merge(
      'google_photos_access_token' => nil,
      'google_photos_refresh_token' => nil,
      'google_photos_token_expires_at' => nil
    )

    if current_user.update(settings: updated_settings)
      redirect_to settings_integrations_path, notice: 'Google Photos disconnected'
    else
      redirect_to settings_integrations_path, alert: 'Failed to disconnect Google Photos'
    end
  end

  private

  def check_google_photos_available
    return if DawarichSettings.google_photos_available?

    redirect_to settings_integrations_path, alert: 'Google Photos integration is not available'
  end

  def authorization_url(state)
    params = {
      client_id: ENV['GOOGLE_OAUTH_CLIENT_ID'],
      redirect_uri: callback_url,
      scope: PHOTOS_SCOPE,
      response_type: 'code',
      access_type: 'offline',
      prompt: 'consent',
      state: state
    }

    "#{GOOGLE_OAUTH_URL}?#{params.to_query}"
  end

  def callback_url
    google_photos_oauth_callback_url
  end

  def valid_state?
    params[:state].present? && params[:state] == session.delete(:google_photos_oauth_state)
  end

  def exchange_code_for_tokens
    response = HTTParty.post(
      GOOGLE_TOKEN_URL,
      body: {
        client_id: ENV['GOOGLE_OAUTH_CLIENT_ID'],
        client_secret: ENV['GOOGLE_OAUTH_CLIENT_SECRET'],
        code: params[:code],
        redirect_uri: callback_url,
        grant_type: 'authorization_code'
      },
      headers: { 'Content-Type' => 'application/x-www-form-urlencoded' },
      timeout: 10
    )

    if response.success?
      parsed = JSON.parse(response.body)
      {
        success: true,
        access_token: parsed['access_token'],
        refresh_token: parsed['refresh_token'],
        expires_in: parsed['expires_in']
      }
    else
      Rails.logger.error("Google Photos token exchange failed: #{response.code} - #{response.body}")
      { success: false, error: 'Token exchange failed' }
    end
  rescue HTTParty::Error, Net::OpenTimeout, Net::ReadTimeout, JSON::ParserError => e
    Rails.logger.error("Google Photos token exchange error: #{e.message}")
    { success: false, error: e.message }
  end

  def save_tokens(result)
    existing_settings = current_user.settings || {}
    expires_at = Time.current.to_i + result[:expires_in].to_i

    updated_settings = existing_settings.merge(
      'google_photos_access_token' => result[:access_token],
      'google_photos_refresh_token' => result[:refresh_token],
      'google_photos_token_expires_at' => expires_at
    )

    current_user.update!(settings: updated_settings)
  end
end

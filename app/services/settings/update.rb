# frozen_string_literal: true

class Settings::Update
  include UrlValidatable

  attr_reader :user, :settings_params, :refresh_photos_cache

  def initialize(user, settings_params, refresh_photos_cache: false)
    @user = user
    @settings_params = settings_params
    @refresh_photos_cache = refresh_photos_cache
  end

  def call
    existing_settings = user.safe_settings.settings
    updated_settings = existing_settings.merge(cast_boolean_params(settings_params))

    immich_changed = settings_changed?(existing_settings, updated_settings, %w[immich_url immich_api_key])
    photoprism_changed = settings_changed?(existing_settings, updated_settings, %w[photoprism_url photoprism_api_key])

    %w[immich_url photoprism_url].each do |key|
      next if updated_settings[key].blank?

      validate_integration_url!(updated_settings[key])
    rescue UrlValidatable::BlockedUrlError => e
      return { success: false, notices: [], alerts: ["#{key.humanize} is not allowed: #{e.message}"] }
    end

    unless user.update(settings: updated_settings)
      return { success: false, notices: [], alerts: ['Settings could not be updated'] }
    end

    notices = ['Settings updated']
    alerts = []

    if refresh_photos_cache
      Photos::CacheCleaner.new(user).call
      notices << 'Photo cache refreshed'
    end

    test_immich_connection(updated_settings, notices, alerts) if immich_changed
    test_photoprism_connection(updated_settings, notices, alerts) if photoprism_changed

    { success: true, notices: notices, alerts: alerts }
  end

  private

  BOOLEAN_KEYS = %w[immich_skip_ssl_verification photoprism_skip_ssl_verification].freeze

  def cast_boolean_params(params)
    params.to_h.tap do |h|
      BOOLEAN_KEYS.each do |key|
        h[key] = ActiveModel::Type::Boolean.new.cast(h[key]) if h.key?(key)
      end
    end
  end

  def settings_changed?(existing_settings, updated_settings, keys)
    keys.any? { |key| existing_settings[key] != updated_settings[key] }
  end

  def test_immich_connection(updated_settings, notices, alerts)
    result = Immich::ConnectionTester.new(
      updated_settings['immich_url'],
      updated_settings['immich_api_key'],
      skip_ssl_verification: updated_settings['immich_skip_ssl_verification']
    ).call
    result[:success] ? notices << result[:message] : alerts << result[:error]
  end

  def test_photoprism_connection(updated_settings, notices, alerts)
    result = Photoprism::ConnectionTester.new(
      updated_settings['photoprism_url'],
      updated_settings['photoprism_api_key'],
      skip_ssl_verification: updated_settings['photoprism_skip_ssl_verification']
    ).call
    result[:success] ? notices << result[:message] : alerts << result[:error]
  end
end

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
    airtrail_changed = settings_changed?(existing_settings, updated_settings, %w[airtrail_url airtrail_api_key])

    %w[immich_url photoprism_url airtrail_url].each do |key|
      next if updated_settings[key].blank?

      validate_integration_url!(updated_settings[key])
    rescue UrlValidatable::BlockedUrlError => e
      return {
        success: false,
        notices: [],
        alerts: [I18n.t('services.settings.update.not_allowed', setting: key.humanize, message: e.message)]
      }
    end

    unless user.update(settings: updated_settings)
      return { success: false, notices: [], alerts: [I18n.t('services.settings.update.failed')] }
    end

    notices = [I18n.t('services.settings.update.updated')]
    alerts = []

    if refresh_photos_cache
      Photos::CacheCleaner.new(user).call
      notices << I18n.t('services.settings.update.photo_cache_refreshed')
    end

    statuses = {}
    test_immich_connection(updated_settings, notices, alerts, statuses) if immich_changed
    test_photoprism_connection(updated_settings, notices, alerts, statuses) if photoprism_changed
    test_airtrail_connection(updated_settings, notices, alerts, statuses) if airtrail_changed
    user.update(settings: user.settings.merge(statuses)) if statuses.any?

    { success: true, notices: notices, alerts: alerts }
  end

  private

  BOOLEAN_KEYS = %w[immich_skip_ssl_verification photoprism_skip_ssl_verification
                    airtrail_skip_ssl_verification].freeze

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

  def test_immich_connection(updated_settings, notices, alerts, statuses)
    result = Immich::ConnectionTester.new(
      updated_settings['immich_url'],
      updated_settings['immich_api_key'],
      skip_ssl_verification: updated_settings['immich_skip_ssl_verification']
    ).call
    record_result('immich', result, notices, alerts, statuses)
  end

  def test_photoprism_connection(updated_settings, notices, alerts, statuses)
    result = Photoprism::ConnectionTester.new(
      updated_settings['photoprism_url'],
      updated_settings['photoprism_api_key'],
      skip_ssl_verification: updated_settings['photoprism_skip_ssl_verification']
    ).call
    record_result('photoprism', result, notices, alerts, statuses)
  end

  def test_airtrail_connection(updated_settings, notices, alerts, statuses)
    result = AirTrail::ConnectionTester.new(
      updated_settings['airtrail_url'],
      updated_settings['airtrail_api_key'],
      skip_ssl_verification: updated_settings['airtrail_skip_ssl_verification']
    ).call
    record_result('airtrail', result, notices, alerts, statuses)
  end

  def record_result(service, result, notices, alerts, statuses)
    result[:success] ? notices << result[:message] : alerts << result[:error]
    statuses["#{service}_connection_status"] = result[:success] ? 'ok' : 'failed'
  end
end

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
    params_hash = cast_boolean_params(settings_params)
    reset_teslamate_checkpoint(params_hash, existing_settings)
    updated_settings = existing_settings.merge(params_hash)

    immich_changed = settings_changed?(existing_settings, updated_settings,
                                       %w[immich_url immich_api_key immich_skip_ssl_verification])
    photoprism_changed = settings_changed?(existing_settings, updated_settings,
                                           %w[photoprism_url photoprism_api_key photoprism_skip_ssl_verification])
    airtrail_changed = settings_changed?(existing_settings, updated_settings,
                                         %w[airtrail_url airtrail_api_key airtrail_skip_ssl_verification])
    teslamate_changed = settings_changed?(
      existing_settings,
      updated_settings,
      %w[teslamate_url teslamate_username teslamate_password teslamate_api_token
         teslamate_skip_ssl_verification]
    )

    %w[immich_url photoprism_url airtrail_url teslamate_url].each do |key|
      next if updated_settings[key].blank?

      validate_integration_url!(updated_settings[key])
    rescue UrlValidatable::BlockedUrlError => e
      return {
        success: false,
        notices: [],
        alerts: [I18n.t('services.settings.update.not_allowed', setting: key.humanize, message: e.message)]
      }
    end

    test_notices = []
    alerts = []
    statuses = {}
    test_immich_connection(updated_settings, test_notices, alerts, statuses) if immich_changed
    test_photoprism_connection(updated_settings, test_notices, alerts, statuses) if photoprism_changed
    test_airtrail_connection(updated_settings, test_notices, alerts, statuses) if airtrail_changed
    test_teslamate_connection(updated_settings, test_notices, alerts, statuses) if teslamate_changed

    # The connection tests above take seconds; re-read settings so a write that
    # landed in the meantime is not reverted by this save.
    final_settings = user.reload.settings.merge(params_hash).merge(statuses)
    unless user.update(settings: final_settings)
      return { success: false, notices: [], alerts: [I18n.t('services.settings.update.failed')] }
    end

    notices = [I18n.t('services.settings.update.updated')]

    if refresh_photos_cache
      Photos::CacheCleaner.new(user).call
      notices << I18n.t('services.settings.update.photo_cache_refreshed')
    end

    { success: true, notices: notices + test_notices, alerts: alerts }
  end

  private

  BOOLEAN_KEYS = %w[immich_skip_ssl_verification photoprism_skip_ssl_verification
                    airtrail_skip_ssl_verification teslamate_skip_ssl_verification].freeze

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

  def reset_teslamate_checkpoint(params, existing_settings)
    return unless params.key?('teslamate_url')
    return if params['teslamate_url'] == existing_settings['teslamate_url']

    params['teslamate_last_synced_at'] = nil
    params['teslamate_last_synced_url'] = nil
    params['teslamate_processing_pending'] = false
    params['teslamate_processing_pending_url'] = nil
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

  def test_teslamate_connection(updated_settings, notices, alerts, statuses)
    result = TeslaMate::ConnectionTester.new(
      updated_settings['teslamate_url'],
      username: updated_settings['teslamate_username'],
      password: updated_settings['teslamate_password'],
      api_token: updated_settings['teslamate_api_token'],
      skip_ssl_verification: updated_settings['teslamate_skip_ssl_verification']
    ).call
    record_result('teslamate', result, notices, alerts, statuses)
  end

  def record_result(service, result, notices, alerts, statuses)
    result[:success] ? notices << result[:message] : alerts << result[:error]
    statuses["#{service}_connection_status"] = result[:success] ? 'ok' : 'failed'
  end
end

# frozen_string_literal: true

class Settings::GeocodingController < ApplicationController
  include FlashStreamable

  TEST_COORDINATES = [51.3402, 12.3712].freeze

  before_action :authenticate_self_hosted!
  before_action :authenticate_user!

  def show
    redirect_to settings_integrations_path(service: 'geocoding')
  end

  def update
    return disable_geocoding if params[:provider] == 'disabled'

    unless Geocoding::Providers::CHAIN.include?(params[:provider])
      return redirect_to geocoding_pane_path, alert: t('settings.geocoding.update.invalid_provider'),
                         status: :see_other
    end

    setting = upsert_setting

    if setting.errors.any?
      redirect_to geocoding_pane_path, alert: setting.errors.full_messages.to_sentence, status: :see_other
    else
      redirect_to geocoding_pane_path, notice: t('settings.geocoding.update.updated')
    end
  end

  def test
    type, message = run_provider_test

    respond_to do |format|
      format.turbo_stream { render turbo_stream: stream_flash(type, message) }
      format.html do
        flash_key = type == :notice ? :notice : :alert
        redirect_to geocoding_pane_path, flash_key => message
      end
    end
  end

  private

  def geocoding_pane_path
    settings_integrations_path(service: 'geocoding')
  end

  def geocoding_settings
    current_user.service_settings.service_geocoding
  end

  def disable_geocoding
    geocoding_settings.update_all(active: false)
    redirect_to geocoding_pane_path, notice: t('settings.geocoding.update.disabled')
  end

  def upsert_setting
    provider = params[:provider]
    setting = geocoding_settings.find_or_initialize_by(provider: provider)
    apply_provider_params(setting,
                          params.fetch(provider, {})
                                .permit(:host, :api_key, :use_https, :clear_api_key, :rps))

    setting.activate! if setting.errors.empty? && setting.save
    setting
  end

  def apply_provider_params(setting, provider_params)
    setting.config['host'] = provider_params[:host] if provider_params.key?(:host)
    if provider_params.key?(:use_https)
      setting.config['use_https'] = ActiveModel::Type::Boolean.new.cast(provider_params[:use_https])
    end
    apply_rps(setting, provider_params)

    if ActiveModel::Type::Boolean.new.cast(provider_params[:clear_api_key])
      setting.api_key = nil
    elsif provider_params[:api_key].present?
      setting.api_key = provider_params[:api_key]
    end

    setting.config.delete('connection_status') if setting.changed?
  end

  # Cast to the stored type before assigning so re-submitting an unchanged form
  # does not read as an edit and wipe the recorded connection status. The model
  # remains the authority on what the rate is allowed to be.
  def apply_rps(setting, provider_params)
    return unless provider_params.key?(:rps)

    rate = provider_params[:rps].presence&.to_f

    if rate
      setting.config['rps'] = rate
    else
      setting.config.delete('rps')
    end
  end

  def run_provider_test
    config = Geocoding::Config.for_user_settings(current_user)
    return [:error, t('settings.geocoding.test.not_configured')] unless config.enabled?

    result = Geocoding::Search.with_config(config: config, query: TEST_COORDINATES, limit: 1).first
    if result
      record_test_result('ok')
      place = [result.city, result.country].compact_blank.join(', ')
      [:notice, t('settings.geocoding.test.success', place: place.presence || result.address)]
    else
      record_test_result('failed')
      [:error, t('settings.geocoding.test.empty')]
    end
  rescue StandardError => e
    record_test_result('failed')
    [:error, t('settings.geocoding.test.failure', error: "#{e.class}: #{e.message}")]
  end

  def record_test_result(status)
    setting = geocoding_settings.find_by(active: true)
    return unless setting

    setting.config['connection_status'] = status
    setting.update_column(:config, setting.config)
  end
end

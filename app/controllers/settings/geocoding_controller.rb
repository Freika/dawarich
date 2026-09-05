# frozen_string_literal: true

class Settings::GeocodingController < ApplicationController
  include FlashStreamable
  include UrlValidatable

  TEST_COORDINATES = [51.3402, 12.3712].freeze
  TEST_MAX_WAIT = 5.0
  SAFE_TEST_ERRORS = [
    SocketError, Resolv::ResolvError, Timeout::Error, OpenSSL::SSL::SSLError,
    Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH, Errno::ENETUNREACH,
    Geocoder::Error
  ].freeze

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

    verify_host_address(setting) if setting.valid?
    setting.activate! if setting.errors.empty? && setting.save
    setting
  end

  # An unresolvable host stays saveable: the web container may lack DNS for a
  # host the Sidekiq container can reach, and AirTrail treats the same case as
  # a reported connection failure rather than a rejected save. Resolvability
  # is probed with getaddrinfo because numeric IPv4 forms (decimal or hex)
  # resolve there — and in the HTTP client — but not in Resolv, which the
  # blocklist check uses.
  def verify_host_address(setting)
    host = setting.config['host']
    return if host.blank? || setting.komoot? || setting.chibigeo?

    scheme = setting.config['use_https'] == false ? 'http' : 'https'
    validate_integration_url!("#{scheme}://#{host}")
  rescue UrlValidatable::BlockedUrlError => e
    return if unresolvable_host?(host)

    setting.errors.add(:base, :host_blocked, reason: blocked_reason(e, host))
  end

  # Resolv cannot read numeric IPv4 forms, so it reports them as unresolvable.
  # getaddrinfo has already proven the host resolves by the time we get here,
  # which makes that message wrong: the address is blocked, not unknown.
  def blocked_reason(error, host)
    resolver_message = I18n.t('services.concerns.url_validatable.unresolvable_host',
                              host: URI.parse("https://#{host}").host.to_s)
    return I18n.t('services.concerns.url_validatable.blocked_address') if error.message == resolver_message

    error.message
  end

  def unresolvable_host?(host)
    Socket.getaddrinfo(URI.parse("https://#{host}").host.to_s, nil)
    false
  rescue SocketError, URI::InvalidURIError
    true
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

    result_set = Geocoding::Search.with_config(config: config, query: TEST_COORDINATES, limit: 1,
                                               timeout: REVERSE_GEOCODING_TIMEOUT,
                                               max_wait: TEST_MAX_WAIT)
    return [:error, t('settings.geocoding.test.rate_limited')] if result_set.nil?

    result = result_set.first
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
    Rails.logger.error("Geocoding provider test failed: #{e.class}: #{e.message}")
    [:error, t('settings.geocoding.test.failure', error: test_error_description(e))]
  end

  def test_error_description(error)
    return "#{error.class}: #{error.message}" if SAFE_TEST_ERRORS.any? { |klass| error.is_a?(klass) }

    error.class.name
  end

  def record_test_result(status)
    setting = geocoding_settings.find_by(active: true)
    return unless setting

    setting.config['connection_status'] = status
    setting.update_column(:config, setting.config)
  end
end

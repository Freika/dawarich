# frozen_string_literal: true

module Geocoding
  # Carries an existing per-user geocoding configuration up to the Instance
  # setting that now owns it.
  #
  # Deliberately conservative: it writes only when every active configuration
  # agrees. Electing one user's provider for the whole deployment would be data
  # loss dressed as a migration, and the hand-edited instance is exactly the one
  # worth not clobbering. Nothing is ever deleted, so the move is reversible.
  class BackfillInstanceSettings
    KEY_FOR_HOST = { 'photon' => :photon_api_host, 'nominatim' => :nominatim_api_host }.freeze
    KEY_FOR_API_KEY = {
      'photon' => :photon_api_key, 'nominatim' => :nominatim_api_key,
      'geoapify' => :geoapify_api_key, 'locationiq' => :locationiq_api_key
    }.freeze

    def self.call
      new.call
    end

    def call
      settings = ServiceSetting.service_geocoding.where(active: true).to_a
      return if settings.empty?

      distinct = settings.map { |s| signature(s) }.uniq
      return log_disagreement(distinct) if distinct.size > 1

      write(settings.first)
    end

    private

    def signature(setting)
      [setting.provider, setting.config['host'], setting.config['use_https'], safe_api_key(setting)]
    end

    # An undecryptable row must not raise the whole migration, and must not be
    # mistaken for an agreeing one either.
    def safe_api_key(setting)
      setting.readable_credentials? ? setting.api_key : :unreadable
    end

    # The signature carries a decrypted API key so configurations can be compared;
    # it must never reach a log. Only provider/host/use_https are printable, and
    # the key is reduced to whether one is present.
    def log_disagreement(distinct)
      redacted = distinct.map do |provider, host, use_https, api_key|
        { provider: provider, host: host, use_https: use_https, api_key: api_key.present? ? '[redacted]' : nil }
      end

      Rails.logger.warn(
        '[Geocoding] active geocoding settings disagree across users; writing no instance setting. ' \
        "Configurations seen: #{redacted.inspect}"
      )
    end

    def write(setting)
      host_key = KEY_FOR_HOST[setting.provider]
      store(host_key, setting.config['host']) if host_key

      store(KEY_FOR_API_KEY[setting.provider], safe_api_key(setting))
      store(:photon_api_use_https, setting.config['use_https']) if setting.provider == 'photon'
      store(:nominatim_api_use_https, setting.config['use_https']) if setting.provider == 'nominatim'
      store(:reverse_geocoding_rps, setting.config['rps'])
    end

    # Never overwrites: an operator who already set a value in the admin page
    # has made a more recent decision than the row being migrated.
    # `blank?` would drop `use_https: false`, and the registry default for
    # nominatim is `true` — silently flipping a plain-HTTP host to HTTPS and
    # breaking geocoding the first time the flag is turned on.
    def store(key, value)
      return if key.nil? || value.nil? || value == :unreadable
      return if value.respond_to?(:empty?) && value.empty?
      return if InstanceSetting.exists?(key: key.to_s)

      InstanceSetting.create!(key: key.to_s, value: value)
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
      Rails.logger.warn("[Geocoding] could not backfill #{key}: #{e.class}: #{e.message}")
    end
  end
end

# frozen_string_literal: true

module InstanceSettings
  # Carries existing configuration into Instance settings so it survives the
  # variables being removed later: every variable that is set, then — only when
  # the environment names no geocoding provider — per-user geocoding rows.
  #
  # The per-user copy is deliberately conservative: it writes only when every
  # user has an active configuration and they all agree. Electing one user's provider for the whole
  # deployment would be data loss dressed as a migration, and the hand-edited
  # instance is exactly the one worth not clobbering. Nothing is ever deleted,
  # so the move is reversible.
  class Backfill
    KEY_FOR_HOST = { 'photon' => :photon_api_host, 'nominatim' => :nominatim_api_host }.freeze
    KEY_FOR_API_KEY = {
      'photon' => :photon_api_key, 'nominatim' => :nominatim_api_key,
      'geoapify' => :geoapify_api_key, 'locationiq' => :locationiq_api_key
    }.freeze

    def self.call
      new.call
    end

    def call
      copy_environment
      copy_user_settings unless environment_names_a_provider?
    end

    private

    def copy_environment
      copied = Registry::DEFINITIONS.values.filter_map do |definition|
        raw = ENV.fetch(definition.env_var, nil)
        next if raw.to_s.strip.empty?

        definition.env_var if store(definition.key, definition.coerce(raw))
      end
      return if copied.empty?

      Rails.logger.info("[InstanceSettings] copied from the environment: #{copied.join(', ')}")
    end

    # A provider chosen by a variable is the instance's decision; copying a
    # different one from old per-user rows would surface it the day the
    # variable is removed.
    def environment_names_a_provider?
      Geocoding::Config::PROVIDER_KEYS.values.any? do |key|
        ENV.fetch(Registry.fetch(key).env_var, nil).to_s.strip.present?
      end
    end

    def copy_user_settings
      settings = ServiceSetting.service_geocoding.where(active: true, user_id: User.select(:id)).to_a
      return if settings.empty?
      return log_partial_coverage if User.where.not(id: settings.map(&:user_id)).exists?

      distinct = settings.map { |s| signature(s) }.uniq
      return log_disagreement(distinct) if distinct.size > 1

      write(settings.first)
    end

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

    # A configuration only some users made is theirs, not the instance's: its API
    # key would otherwise start serving, and billing, every other user.
    def log_partial_coverage
      Rails.logger.warn(
        '[Geocoding] not every user has an active geocoding setting; writing no instance setting.'
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
      return false if key.nil? || value.nil? || value == :unreadable
      return false if value.respond_to?(:empty?) && value.empty?
      return false if InstanceSetting.exists?(key: key.to_s)

      InstanceSetting.create!(key: key.to_s, value: value)
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
      Rails.logger.warn("[InstanceSettings] could not backfill #{key}: #{e.class}")
      false
    end
  end
end

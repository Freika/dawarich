# frozen_string_literal: true

class DawarichSettings
  BASIC_PAID_PLAN_LIMIT = 10_000_000 # 10 million points
  LITE_DATA_WINDOW = 12.months

  class << self
    def reverse_geocoding_enabled?
      @reverse_geocoding_enabled ||= photon_enabled? || geoapify_enabled? || nominatim_enabled? || locationiq_enabled?
    end

    def photon_enabled?
      @photon_enabled ||= PHOTON_API_HOST.present?
    end

    def photon_uses_komoot_io?
      @photon_uses_komoot_io ||= PHOTON_API_HOST == 'photon.komoot.io'
    end

    def geoapify_enabled?
      @geoapify_enabled ||= GEOAPIFY_API_KEY.present?
    end

    def locationiq_enabled?
      @locationiq_enabled ||= LOCATIONIQ_API_KEY.present?
    end

    def self_hosted?
      @self_hosted ||= SELF_HOSTED
    end

    def prometheus_exporter_enabled?
      @prometheus_exporter_enabled ||=
        ENV['PROMETHEUS_EXPORTER_ENABLED'].to_s == 'true' &&
        ENV['PROMETHEUS_EXPORTER_HOST'].present? &&
        ENV['PROMETHEUS_EXPORTER_PORT'].present?
    end

    def nominatim_enabled?
      @nominatim_enabled ||= NOMINATIM_API_HOST.present?
    end

    def store_geodata?
      @store_geodata ||= STORE_GEODATA
    end

    def family_feature_enabled?
      @family_feature_enabled ||= self_hosted?
    end

    # Returns true only for self-hosted OIDC (OpenID Connect) setups.
    # Cloud mode OAuth (GitHub, Google) is always supplementary to email/password
    # and should not trigger OIDC-only mode restrictions.
    def oidc_enabled?
      @oidc_enabled ||= self_hosted? && OMNIAUTH_PROVIDERS.include?(:openid_connect)
    end

    def features
      @features ||= {
        reverse_geocoding: reverse_geocoding_enabled?,
        family: family_feature_enabled?
      }
    end

    def gapfill_enabled?
      @gapfill_enabled ||= ENV['BROUTER_URL'].present?
    end

    def archive_raw_data_enabled?
      @archive_raw_data_enabled ||= ARCHIVE_RAW_DATA
    end

    def two_factor_available?
      @two_factor_available ||=
        ENV['OTP_ENCRYPTION_PRIMARY_KEY'].present? &&
        ENV['OTP_ENCRYPTION_DETERMINISTIC_KEY'].present? &&
        ENV['OTP_ENCRYPTION_KEY_DERIVATION_SALT'].present?
    end

    def registration_enabled?
      Rails.cache.fetch('dawarich/registration_enabled') { ALLOW_EMAIL_PASSWORD_REGISTRATION }
    end

    def set_registration_enabled(enabled)
      Rails.cache.write('dawarich/registration_enabled', enabled)
    end
  end
end

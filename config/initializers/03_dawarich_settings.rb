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

    def photon_https_only_host?
      @photon_https_only_host ||= PHOTON_HTTPS_ONLY_HOSTS.include?(normalized_photon_host)
    end

    def normalized_photon_host
      PHOTON_API_HOST.to_s.strip.downcase.split(':').first
    end

    def photon_use_https?
      @photon_use_https ||= PHOTON_API_USE_HTTPS || photon_https_only_host?
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
      ENV['PROMETHEUS_EXPORTER_ENABLED'].to_s == 'true'
    end

    def email_configured?
      ENV['SMTP_SERVER'].present?
    end

    def nominatim_enabled?
      @nominatim_enabled ||= NOMINATIM_API_HOST.present?
    end

    def store_geodata?
      @store_geodata ||= STORE_GEODATA
    end

    # Self-hosted instances grant the family feature to everyone. On cloud it is
    # part of the Family subscription plan, so access follows the user's plan
    # rather than the hosting mode.
    #
    # Deliberately not memoized: the answer depends on the user, and
    # DawarichSettings is a process-wide singleton.
    def family_feature_available_for?(user)
      return true if self_hosted?
      return false if user.nil?

      # Entitlements models the rule: the plan holder gets the feature, and so
      # does everyone in a family whose owner holds it. When the owner's plan
      # lapses, the whole family drops back together.
      user.entitlements.families?
    end

    # Returns true only for self-hosted OIDC (OpenID Connect) setups.
    # Cloud mode OAuth (GitHub, Google) is always supplementary to email/password
    # and should not trigger OIDC-only mode restrictions.
    def oidc_enabled?
      @oidc_enabled ||= self_hosted? && OMNIAUTH_PROVIDERS.include?(:openid_connect)
    end

    def features_for(user)
      {
        reverse_geocoding: Geocoding::Config.for(user).enabled?,
        family: family_feature_available_for?(user)
      }
    end

    def archive_raw_data_enabled?
      @archive_raw_data_enabled ||= ARCHIVE_RAW_DATA
    end

    # 0 (or a negative value) disables the age limit; videos then live until
    # the per-user cap evicts them, or the user deletes them.
    def video_retention_days
      @video_retention_days ||= [VIDEO_RETENTION_DAYS, 0].max
    end

    # 0 (or a negative value) disables the per-user cap.
    def video_max_per_user
      @video_max_per_user ||= [VIDEO_MAX_PER_USER, 0].max
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

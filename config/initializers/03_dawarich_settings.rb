# frozen_string_literal: true

class DawarichSettings
  BASIC_PAID_PLAN_LIMIT = 10_000_000 # 10 million points
  LITE_DATA_WINDOW = 12.months

  class << self
    def reverse_geocoding_enabled?
      return @reverse_geocoding_enabled if defined?(@reverse_geocoding_enabled)

      @reverse_geocoding_enabled ||= photon_enabled? || geoapify_enabled? || nominatim_enabled? || locationiq_enabled?
    end

    def photon_enabled?
      return @photon_enabled if defined?(@photon_enabled)

      @photon_enabled = PHOTON_API_HOST.present?
    end

    def photon_uses_komoot_io?
      return @photon_uses_komoot_io if defined?(@photon_uses_komoot_io)

      @photon_uses_komoot_io = PHOTON_API_HOST == 'photon.komoot.io'
    end

    def geoapify_enabled?
      return @geoapify_enabled if defined?(@geoapify_enabled)

      @geoapify_enabled = GEOAPIFY_API_KEY.present?
    end

    def locationiq_enabled?
      @locationiq_enabled ||= LOCATIONIQ_API_KEY.present?
    end

    def self_hosted?
      return @self_hosted if defined?(@self_hosted)

      @self_hosted = SELF_HOSTED
    end

    def prometheus_exporter_enabled?
      return @prometheus_exporter_enabled if defined?(@prometheus_exporter_enabled)

      @prometheus_exporter_enabled =
        ENV['PROMETHEUS_EXPORTER_ENABLED'].to_s == 'true' &&
        ENV['PROMETHEUS_EXPORTER_HOST'].present? &&
        ENV['PROMETHEUS_EXPORTER_PORT'].present?
    end

    def nominatim_enabled?
      return @nominatim_enabled if defined?(@nominatim_enabled)

      @nominatim_enabled = NOMINATIM_API_HOST.present?
    end

    def store_geodata?
      return @store_geodata if defined?(@store_geodata)

      @store_geodata = STORE_GEODATA
    end

    def family_feature_enabled?
      return @family_feature_enabled if defined?(@family_feature_enabled)

      @family_feature_enabled = self_hosted?
    end

    # Returns true only for self-hosted OIDC (OpenID Connect) setups.
    # Cloud mode OAuth (GitHub, Google) is always supplementary to email/password
    # and should not trigger OIDC-only mode restrictions.
    def oidc_enabled?
      return @oidc_enabled if defined?(@oidc_enabled)

      @oidc_enabled = self_hosted? && OMNIAUTH_PROVIDERS.include?(:openid_connect)
    end

    def features
      @features ||= {
        reverse_geocoding: reverse_geocoding_enabled?,
        family: family_feature_enabled?
      }
    end

    def archive_raw_data_enabled?
      return @archive_raw_data_enabled if defined?(@archive_raw_data_enabled)

      @archive_raw_data_enabled = ARCHIVE_RAW_DATA
    end

    def video_service_enabled?
      Rails.cache.fetch('video_service_enabled', expires_in: 15.minutes) do
        video_service_healthy?
      end
    end

    private

    def video_service_healthy?
      url = ENV['VIDEO_SERVICE_URL']
      return false if url.blank?

      uri = URI.parse("#{url.chomp('/')}/health")
      response = Net::HTTP.start(
        uri.host, uri.port,
        use_ssl: uri.scheme == 'https',
        open_timeout: 1, read_timeout: 1
      ) { |http| http.get(uri.path) }

      return false unless response.is_a?(Net::HTTPSuccess)

      body = JSON.parse(response.body)
      body['status'] == 'ok'
    rescue StandardError
      false
    end

    def registration_enabled?
      Rails.cache.fetch('dawarich/registration_enabled') { ALLOW_EMAIL_PASSWORD_REGISTRATION }
    end

    def set_registration_enabled(enabled)
      Rails.cache.write('dawarich/registration_enabled', enabled)
    end
  end
end

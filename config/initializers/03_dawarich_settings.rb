# frozen_string_literal: true

class DawarichSettings
  BASIC_PAID_PLAN_LIMIT = 10_000_000 # 10 million points

  class << self
    def reverse_geocoding_enabled?
      @reverse_geocoding_enabled ||= photon_enabled? || geoapify_enabled? || nominatim_enabled?
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

    def features
      @features ||= {
        reverse_geocoding: reverse_geocoding_enabled?,
        family: family_feature_enabled?
      }
    end

    def archive_raw_data_enabled?
      @archive_raw_data_enabled ||= ARCHIVE_RAW_DATA
    end
  end
end

# frozen_string_literal: true

class DawarichSettings
  class << self
    def config
      {
        reverse_geocoding_enabled: reverse_geocoding_enabled?,
        photon_enabled: photon_enabled?,
        photon_uses_komoot_io: photon_uses_komoot_io?,
        geoapify_enabled: geoapify_enabled?,
        meters_between_tracks: meters_between_tracks,
        minutes_between_tracks: minutes_between_tracks
      }
    end

    def reverse_geocoding_enabled?
      @reverse_geocoding_enabled ||= photon_enabled? || geoapify_enabled?
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

    def meters_between_tracks
      @meters_between_tracks ||= 500
    end

    def minutes_between_tracks
      @minutes_between_tracks ||= 30
    end
  end
end

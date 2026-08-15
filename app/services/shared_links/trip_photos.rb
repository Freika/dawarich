# frozen_string_literal: true

module SharedLinks
  class TripPhotos
    def initialize(link, timezone:)
      @link = link
      @timezone = timezone.presence || 'UTC'
    end

    def call
      zone = Time.find_zone(@timezone) || Time.find_zone('UTC')

      mappable_photos.each_with_object({}) do |photo, acc|
        raw = photo[:capturedAt] || photo[:localDateTime]
        date = parse_date(raw, zone)
        next if date.nil?

        (acc[date] ||= []) << {
          id: photo[:id],
          source: photo[:source],
          taken_at: raw
        }
      end
    end

    private

    def mappable_photos
      Photos::Mappable.new(search_photos, privacy_zones: Users::PrivacyZones.new(@link.user).call).call
    end

    def search_photos
      trip = @link.resource
      return [] if trip.nil?

      Photos::Search.cached(@link.user, start_date: trip.started_at.iso8601, end_date: trip.ended_at.iso8601)
    end

    def parse_date(raw, zone)
      return nil if raw.blank?

      zone.parse(raw.to_s)&.to_date
    rescue ArgumentError, TypeError
      nil
    end
  end
end

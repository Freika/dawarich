# frozen_string_literal: true

module Api
  module V1
    module Shared
      class PhotosController < BaseController
        MAX_PHOTOS = 100

        def index
          return render(json: []) unless ctx.show_photos?

          cache_public_for(60.seconds)
          render json: mappable_photos.map { |p| serialize(p) }
        rescue StandardError => e
          Rails.logger.error("Shared photos fetch failed: #{e.class} #{e.message}")
          render json: []
        end

        def thumbnail
          return head(:not_found) unless ctx.show_photos?
          return head(:not_found) unless allowed_photo?(params[:photo_id], params[:source])

          upstream = Photos::Thumbnail.new(link.user, params[:source], params[:photo_id]).call
          return head(:not_found) unless upstream.success?

          send_data upstream.body, type: 'image/jpeg', disposition: 'inline'
        rescue StandardError => e
          Rails.logger.error("Shared thumbnail fetch failed: #{e.class} #{e.message}")
          head :not_found
        end

        private

        # Geotagged photos in the shared window, capped so a long trip doesn't
        # flood the map with markers (and the browser with thumbnail requests).
        def mappable_photos
          photos = capped_geotagged(fetch_photos)
          Rails.cache.write(allowed_ids_cache_key, allowed_ids_for(photos), expires_in: 10.minutes)
          photos
        end

        # Cache the id set so each thumbnail request validates against it instead
        # of re-running the (expensive) photo search on every single thumbnail.
        def allowed_photo?(photo_id, source)
          ids = Rails.cache.fetch(allowed_ids_cache_key, expires_in: 10.minutes) do
            allowed_ids_for(capped_geotagged(fetch_photos))
          end
          ids.include?("#{source}:#{photo_id}")
        end

        def capped_geotagged(photos)
          photos.select { |p| p[:latitude].present? && p[:longitude].present? }
                .reject { |p| within_privacy_zone?(p[:latitude], p[:longitude]) }
                .first(MAX_PHOTOS)
        end

        def allowed_ids_for(photos)
          photos.map { |p| "#{p[:source]}:#{p[:id]}" }
        end

        def allowed_ids_cache_key
          "shared_link/#{link.id}/photo_ids/#{privacy_zones_fingerprint}"
        end

        def privacy_zones_fingerprint
          Digest::MD5.hexdigest(privacy_zones.sort_by { |z| [z[:lat], z[:lon], z[:radius]] }.to_s)
        end

        # Use Photos::Search (not Trips::Photos) because the shared map needs each
        # photo's latitude/longitude, which Trips::Photos strips for its gallery view.
        def fetch_photos
          range = photo_range
          return [] if range.nil?

          Photos::Search.new(link.user, start_date: range.first, end_date: range.last).call
        end

        def photo_range
          case link.resource_type.to_sym
          when :trip
            trip = link.resource
            return nil if trip.nil?

            [trip.started_at.iso8601, trip.ended_at.iso8601]
          when :track
            track = link.resource
            return nil if track.nil?

            [track.start_at.iso8601, track.end_at.iso8601]
          when :timeline
            zone = Time.find_zone(link.user.timezone_iana) || Time.find_zone('UTC')
            start_at = zone.parse(link.settings['start_date'].to_s)
            end_at   = zone.parse(link.settings['end_date'].to_s)
            return nil if start_at.nil? || end_at.nil?

            [start_at.beginning_of_day.iso8601, end_at.end_of_day.iso8601]
          end
        rescue ArgumentError, TypeError
          nil
        end

        def serialize(photo)
          {
            id: photo[:id],
            latitude: photo[:latitude],
            longitude: photo[:longitude],
            source: photo[:source],
            thumbnail_url: url_for(
              controller: 'api/v1/shared/photos',
              action: 'thumbnail',
              id: link.id,
              photo_id: photo[:id],
              source: photo[:source],
              only_path: true
            )
          }
        end
      end
    end
  end
end

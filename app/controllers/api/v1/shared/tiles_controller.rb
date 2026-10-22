# frozen_string_literal: true

module Api
  module V1
    module Shared
      class TilesController < BaseController
        include TileResponse

        TILE_SCHEMA_VERSION = 1
        PUBLIC_MAX_AGE = 30.seconds

        def show
          started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          return render(json: { error: 'not_found' }, status: :not_found) unless trip_route_shared?
          return reject_exclude if params[:exclude].present?

          if publicly_cacheable?
            expires_in PUBLIC_MAX_AGE, public: true, must_revalidate: true
            fresh_when(etag: tile_etag, public: true)
            return if performed?
          end

          tile = decode_bytea(tile_query.call.tile)
          keep_private unless publicly_cacheable?
          return head :no_content if tile.blank?

          send_data tile, type: 'application/vnd.mapbox-vector-tile', disposition: 'inline'
        rescue ::Trips::RoutesTileQuery::InvalidTileCoordinatesError
          force_uncacheable_response
          render json: { error: 'Invalid tile coordinates' }, status: :bad_request
        rescue ActiveRecord::QueryCanceled
          force_uncacheable_response
          render json: { error: 'Tile query timed out' }, status: :service_unavailable
        ensure
          record_tile_metrics(started_at) if started_at
        end

        private

        def trip_route_shared?
          link.resource_type.to_sym == :trip && trip.present? && ctx.show_route?
        end

        def trip
          @trip ||= link.resource
        end

        def reject_exclude
          force_uncacheable_response
          render json: { error: 'exclude is not supported for shared links' }, status: :bad_request
        end

        def publicly_cacheable?
          !link.family_only? && link.magic_phrase.blank?
        end

        def keep_private
          response.cache_control.clear
          response.headers['Cache-Control'] = 'private, no-store'
          response.headers['Vary'] = [response.headers['Vary'], 'Cookie'].compact.join(', ')
        end

        def tile_query
          ::Trips::RoutesTileQuery.new(
            trip:, z: params[:z], x: params[:x], y: params[:y], timezone: link.user.timezone_iana,
            points_scope: trip.plan_scoped_route_points, privacy_zones:
          )
        end

        def tile_etag
          [
            TILE_SCHEMA_VERSION, link.id, link.updated_at.to_i, trip.updated_at.to_i,
            Digest::SHA256.hexdigest(privacy_zones.to_json),
            trip.recording_devices_cache_key, link.user.timezone_iana,
            (link.user.data_window_start.to_date if link.user.plan_restricted?), params[:z], params[:x], params[:y]
          ]
        end

        def tile_metric_layer
          'shared_trip'
        end
      end
    end
  end
end

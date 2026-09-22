# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Tiles::Tracks', type: :request do
  let(:user) { create(:user) }
  let(:path) { '/api/v1/tiles/tracks/0/0/0.mvt' }

  def create_track_near_origin(owner = user, attrs = {})
    create(:track, user: owner,
                   original_path: 'LINESTRING(0.001 0.001, 20 20)',
                   start_at: Time.utc(2024, 6, 1, 10), end_at: Time.utc(2024, 6, 1, 12),
                   **attrs)
  end

  describe 'GET /show' do
    it 'provides segment speeds when speed coloring is requested' do
      track = create_track_near_origin(user,
                                       original_path: 'LINESTRING(0.001 0.001, 0.002 0.001, 0.0021 0.001)')
      [0.001, 0.002, 0.0021].each_with_index do |longitude, index|
        create(:point, user:, track:, longitude:, latitude: 0.001,
                       timestamp: track.start_at.to_i + (index * 10))
      end

      get '/api/v1/tiles/tracks/15/16384/16383.mvt',
          params: { api_key: user.api_key, speed_coloring: 'true' }

      expect(response).to have_http_status(:ok)
      expect(response.body.b).to include('segment_speed')
    end

    it 'returns a vector tile with the serializer-matching property set' do
      create_track_near_origin(user, dominant_mode: :driving)

      get path, params: { api_key: user.api_key }

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq('application/vnd.mapbox-vector-tile')

      body = response.body.b
      expect(body).to include("\x1a\x02id".b, 'color', 'start_at', 'end_at',
                              'distance', 'avg_speed', 'duration',
                              'dominant_mode', 'dominant_mode_emoji')
      expect(body).to include('driving'.b, '🚗'.b, '#6366F1'.b)
      expect(body).not_to include('mode_timeline', 'segments', 'original_path')
    end

    it 'returns no content for a user without tracks in the tile' do
      get path, params: { api_key: user.api_key }

      expect(response).to have_http_status(:no_content)
    end

    it 'never serves another user\'s tracks' do
      other = create(:user)
      create_track_near_origin(other)

      get path, params: { api_key: user.api_key }

      expect(response).to have_http_status(:no_content)
    end

    it 'limits tracks to those containing a Point from the selected import' do
      selected_import = create(:import, user:)
      selected_track = create_track_near_origin
      create(:point, user:, track: selected_track, import: selected_import,
                     longitude: 0.001, latitude: 0.001, lonlat: 'POINT(0.001 0.001)')
      create(:point, user:, track: selected_track, import: selected_import,
                     longitude: 0.002, latitude: 0.002, lonlat: 'POINT(0.002 0.002)')
      other_track = create_track_near_origin(
        user, start_at: Time.utc(2024, 6, 2, 10), end_at: Time.utc(2024, 6, 2, 12)
      )
      create(:point, user:, track: other_track, longitude: 0.002, latitude: 0.002,
                     lonlat: 'POINT(0.002 0.002)')
      captured_scope = nil
      allow(Tracks::VectorTileQuery).to receive(:new).and_wrap_original do |original, **attributes|
        captured_scope = attributes.fetch(:scope)
        original.call(**attributes)
      end

      get '/api/v1/tiles/tracks/15/16384/16383.mvt',
          params: { api_key: user.api_key, import_id: selected_import.id }

      expect(response).to have_http_status(:ok)
      expect(captured_scope.ids).to eq([selected_track.id])
    end

    it 'reads neighboring Points for speed continuity without drawing other imports' do
      selected_import = create(:import, user:)
      track = create_track_near_origin(
        user, original_path: 'LINESTRING(0.001 0.001, 0.002 0.001)'
      )
      selected = create(:point, user:, track:, import: selected_import,
                                longitude: 0.001, latitude: 0.001,
                                lonlat: 'POINT(0.001 0.001)', timestamp: track.start_at.to_i)
      selected_endpoint = create(:point, user:, track:, import: selected_import,
                                         longitude: 0.0015, latitude: 0.001,
                                         lonlat: 'POINT(0.0015 0.001)', timestamp: track.start_at.to_i + 5)
      other = create(:point, user:, track:, longitude: 0.002, latitude: 0.001,
                             lonlat: 'POINT(0.002 0.001)', timestamp: track.start_at.to_i + 10)
      captured_points_scope = nil
      allow(Tracks::SpeedVectorTileQuery).to receive(:new).and_wrap_original do |original, **attributes|
        captured_points_scope = attributes.fetch(:points_scope)
        original.call(**attributes)
      end

      get '/api/v1/tiles/tracks/15/16384/16383.mvt',
          params: { api_key: user.api_key, import_id: selected_import.id, speed_coloring: 'true' }

      expect(response).to have_http_status(:ok)
      expect(captured_points_scope.ids).to match_array([selected.id, selected_endpoint.id, other.id])
    end

    describe 'caching lifecycle' do
      let(:range) { { start_at: '2024-01-01T00:00:00Z', end_at: '2024-12-31T23:59:59Z' } }

      it 'invalidates an import-scoped flat tile when one of its Points moves' do
        selected_import = create(:import, user:)
        track = create_track_near_origin(user,
                                         original_path: 'LINESTRING(0.001 0.001, 0.002 0.001)')
        create(:point, user:, track:, import: selected_import, longitude: 0.001,
                       latitude: 0.001, timestamp: track.start_at.to_i)
        endpoint = create(:point, user:, track:, import: selected_import, longitude: 0.002,
                                  latitude: 0.001, timestamp: track.start_at.to_i + 10)
        tile_path = '/api/v1/tiles/tracks/15/16384/16383.mvt'
        params = range.merge(api_key: user.api_key, import_id: selected_import.id)
        get(tile_path, params:)
        expect(response).to have_http_status(:ok)
        etag = response.headers['ETag']
        original_tile = response.body.b

        patch "/api/v1/points/#{endpoint.id}",
              params: { api_key: user.api_key, point: { longitude: 0.0015, latitude: 0.001 } }
        expect(response).to have_http_status(:ok)
        get tile_path, params:, headers: { 'If-None-Match' => etag }

        expect(response).to have_http_status(:ok)
        expect(response.body.b).not_to eq(original_tile)
      end

      it 'does not scan every imported track merely to validate a cached tile' do
        selected_import = create(:import, user:)
        track = create_track_near_origin
        [0.001, 0.002].each do |longitude|
          create(:point, user:, track:, import: selected_import, longitude:, latitude: 0.001)
        end
        params = range.merge(api_key: user.api_key, import_id: selected_import.id)
        tile_path = '/api/v1/tiles/tracks/15/16384/16383.mvt'
        get tile_path, params: params
        etag = response.headers['ETag']
        expect(etag).to be_present

        statements = []
        subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
          statements << payload[:sql]
        end
        begin
          get tile_path, params:, headers: { 'If-None-Match' => etag }
        ensure
          ActiveSupport::Notifications.unsubscribe(subscriber)
        end

        expect(response).to have_http_status(:not_modified)
        expect(statements.grep(/MIN\(start_at\).*MAX\(end_at\)/i)).to be_empty
      end

      it 'does not invalidate clipped import geometry when a Point outside the range changes' do
        selected_import = create(:import, user:)
        track = create_track_near_origin(user, start_at: Time.utc(2024, 12, 31, 23, 59, 50),
                                              end_at: Time.utc(2025, 1, 1, 0, 0, 20),
                                              original_path: 'LINESTRING(0.001 0.001, 0.0015 0.001, 0.002 0.001)')
        endpoint = create(:point, user:, track:, import: selected_import, longitude: 0.001,
                                  latitude: 0.001, timestamp: track.start_at.to_i)
        create(:point, user:, track:, import: selected_import, longitude: 0.0015,
                       latitude: 0.001, timestamp: Time.utc(2025, 1, 1, 0, 0, 5).to_i)
        create(:point, user:, track:, import: selected_import, longitude: 0.002,
                       latitude: 0.001, timestamp: Time.utc(2025, 1, 1, 0, 0, 10).to_i)
        tile_path = '/api/v1/tiles/tracks/15/16384/16383.mvt'
        params = { api_key: user.api_key, import_id: selected_import.id,
                   start_at: '2025-01-01T00:00:00Z', end_at: '2025-01-02T00:00:00Z' }
        get tile_path, params: params
        expect(response).to have_http_status(:ok)
        etag = response.headers['ETag']
        patch "/api/v1/points/#{endpoint.id}",
              params: { api_key: user.api_key, point: { longitude: 0.0015, latitude: 0.001 } }
        expect(response).to have_http_status(:ok)
        get tile_path, params:, headers: { 'If-None-Match' => etag }

        expect(response).to have_http_status(:not_modified)
      end

      it 'separates speed tiles and invalidates them when their points change' do
        track = create_track_near_origin(user,
                                         original_path: 'LINESTRING(0.001 0.001, 0.002 0.001)')
        create(:point, user:, track:, longitude: 0.001, latitude: 0.001, timestamp: track.start_at.to_i)
        endpoint = create(:point, user:, track:, longitude: 0.002, latitude: 0.001,
                                  timestamp: track.start_at.to_i + 10)
        tile_path = '/api/v1/tiles/tracks/15/16384/16383.mvt'
        get tile_path, params: range.merge(api_key: user.api_key)
        flat_etag = response.headers['ETag']

        params = range.merge(api_key: user.api_key, speed_coloring: 'true')
        get tile_path, params:, headers: { 'If-None-Match' => flat_etag }
        expect(response).to have_http_status(:ok)
        speed_etag = response.headers['ETag']
        original_tile = response.body.b

        get tile_path, params:, headers: { 'If-None-Match' => speed_etag }
        expect(response).to have_http_status(:not_modified)

        patch "/api/v1/points/#{endpoint.id}",
              params: { api_key: user.api_key, point: { longitude: 0.0011, latitude: 0.001 } }
        expect(response).to have_http_status(:ok)
        get tile_path, params:, headers: { 'If-None-Match' => speed_etag }

        expect(response).to have_http_status(:ok)
        expect(response.body.b).not_to eq(original_tile)
      end

      it 'does not invalidate a clipped speed tile when a Point outside the range changes' do
        track = create_track_near_origin(user, start_at: Time.utc(2024, 12, 31, 23, 59, 50),
                                              end_at: Time.utc(2025, 1, 1, 0, 0, 20),
                                              original_path: 'LINESTRING(0.001 0.001, 0.0015 0.001, 0.002 0.001)')
        endpoint = create(:point, user:, track:, longitude: 0.001, latitude: 0.001,
                                  timestamp: track.start_at.to_i)
        create(:point, user:, track:, longitude: 0.0015, latitude: 0.001,
                       timestamp: Time.utc(2025, 1, 1, 0, 0, 5).to_i)
        create(:point, user:, track:, longitude: 0.002, latitude: 0.001,
                       timestamp: Time.utc(2025, 1, 1, 0, 0, 10).to_i)
        params = { api_key: user.api_key, speed_coloring: 'true',
                   start_at: '2025-01-01T00:00:00Z', end_at: '2025-01-02T00:00:00Z' }
        tile_path = '/api/v1/tiles/tracks/15/16384/16383.mvt'
        get(tile_path, params:)
        expect(response).to have_http_status(:ok)
        etag = response.headers['ETag']

        patch "/api/v1/points/#{endpoint.id}",
              params: { api_key: user.api_key, point: { longitude: 0.0015, latitude: 0.001 } }
        expect(response).to have_http_status(:ok)
        get tile_path, params:, headers: { 'If-None-Match' => etag }

        expect(response).to have_http_status(:not_modified)
      end

      it 'serves cacheable responses, honors ETags, and invalidates on track writes' do
        track = create_track_near_origin
        create(:point, user:, track:, longitude: 0.001, latitude: 0.001,
                       timestamp: track.start_at.to_i)
        create(:point, user:, track:, longitude: 20, latitude: 20,
                       timestamp: track.start_at.to_i + 10)

        get path, params: range.merge(api_key: user.api_key)
        expect(response).to have_http_status(:ok)
        expect(response.headers['Cache-Control']).to include('max-age=300', 'private')
        expect(response.headers['Vary']).to include('Authorization')
        etag = response.headers['ETag']
        expect(etag).to be_present

        get path, params: range.merge(api_key: user.api_key), headers: { 'If-None-Match' => etag }
        expect(response).to have_http_status(:not_modified)

        create_track_near_origin(user, start_at: Time.utc(2024, 6, 2, 10),
                                       end_at: Time.utc(2024, 6, 2, 12))

        get path, params: range.merge(api_key: user.api_key), headers: { 'If-None-Match' => etag }
        expect(response).to have_http_status(:ok)
      end

      it 'rejects a reversed range with 400 and no-store' do
        get path, params: { api_key: user.api_key,
                            start_at: '2024-12-31T00:00:00Z', end_at: '2024-01-01T00:00:00Z' }

        expect(response).to have_http_status(:bad_request)
        expect(response.headers['Cache-Control']).to include('no-store')
        expect(response.headers['ETag']).to be_nil
      end

      it 'serves rangeless requests uncacheable' do
        create_track_near_origin

        get path, params: { api_key: user.api_key }

        expect(response).to have_http_status(:ok)
        expect(response.headers['Cache-Control']).to include('no-store')
      end
    end

    it 'returns 503 with no-store when the tile query times out' do
      query = instance_double(Tracks::VectorTileQuery)
      allow(Tracks::VectorTileQuery).to receive(:new).and_return(query)
      allow(query).to receive(:call).and_raise(ActiveRecord::QueryCanceled)

      get path, params: { api_key: user.api_key }

      expect(response).to have_http_status(:service_unavailable)
      expect(response.headers['Cache-Control']).to include('no-store')
      expect(response.headers['ETag']).to be_nil
    end

    it 'returns a non-cacheable error rather than a partial tile over the speed feature limit' do
      track = create_track_near_origin(user,
                                       original_path: 'LINESTRING(0.001 0.001, 0.002 0.001, 0.0021 0.001)')
      [0.001, 0.002, 0.0021].each_with_index do |longitude, index|
        create(:point, user:, track:, longitude:, latitude: 0.001,
                       timestamp: track.start_at.to_i + (index * 10))
      end
      stub_const('Tracks::SpeedVectorTileQuery::MAX_SPEED_FEATURES_PER_TILE', 1)

      expect do
        get '/api/v1/tiles/tracks/15/16384/16383.mvt', params: {
          api_key: user.api_key, speed_coloring: 'true',
          start_at: '2024-06-01T00:00:00Z', end_at: '2024-06-02T00:00:00Z'
        }
      end.to increment_yabeda_counter(Yabeda.dawarich_map.tile_requests_total)
        .with_tags(layer: 'tracks', outcome: 'failure')

      expect(response).to have_http_status(:service_unavailable)
      expect(response.headers['Cache-Control']).to include('no-store')
      expect(response.headers['ETag']).to be_nil
      expect(response.parsed_body['error']).to include('Zoom in or shorten the date range')
    end

    it 'returns 400 for invalid tile coordinates' do
      get '/api/v1/tiles/tracks/2/9/0.mvt', params: { api_key: user.api_key }

      expect(response).to have_http_status(:bad_request)
    end

    it 'rejects unauthenticated requests' do
      get path

      expect(response).to have_http_status(:unauthorized)
    end
  end
end

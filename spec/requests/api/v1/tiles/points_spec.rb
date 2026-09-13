# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Tiles::Points', type: :request do
  let(:user) { create(:user) }
  let(:path) { '/api/v1/tiles/points/0/0/0.mvt' }

  describe 'GET /show' do
    it 'returns a vector tile for authenticated requests' do
      create(:point, user:, longitude: 0.0, latitude: 0.0, lonlat: 'POINT(0 0)')

      get path, params: { api_key: user.api_key }

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq('application/vnd.mapbox-vector-tile')
      expect(response.body.bytesize).to be_positive
    end

    it 'names properties to match the map point popup contract at point-tile zooms' do
      create(:point, user:, longitude: 11.6015, latitude: 48.1503, lonlat: 'POINT(11.6015 48.1503)')

      get '/api/v1/tiles/points/10/544/355.mvt', params: { api_key: user.api_key }

      # MVT keys are length-prefixed, so a bare 'id' would also match inside longer keys
      body = response.body.b

      expect(body).to include("\x1a\x02id".b, 'timestamp', 'battery', 'altitude', 'velocity')
      expect(body).to include("\x1a\x08latitude".b, "\x1a\x09longitude".b, "\x1a\x05count".b)
      expect(body).not_to include('point_id')
      expect(body).not_to include('grid_cell')
      expect(body).not_to include('track_id', 'visit_id')
    end

    it 'serves aggregate features without per-point attributes at low zooms' do
      create(:point, user:, longitude: 0.0, latitude: 0.0, lonlat: 'POINT(0 0)')

      get path, params: { api_key: user.api_key }

      body = response.body.b

      expect(response).to have_http_status(:ok)
      expect(body).to include("\x1a\x05count".b)
      expect(body).not_to include("\x1a\x02id".b, 'timestamp')
    end

    it 'returns 503 with no-store when the tile query times out' do
      query = instance_double(Points::VectorTileQuery)
      allow(Points::VectorTileQuery).to receive(:new).and_return(query)
      allow(query).to receive(:call).and_raise(ActiveRecord::QueryCanceled)

      get path, params: { api_key: user.api_key }

      expect(response).to have_http_status(:service_unavailable)
      expect(response.headers['Cache-Control']).to include('no-store')
    end

    it 'flags the impossible truncation case with a response header' do
      result = Points::VectorTileQuery::Result.new(tile: 'tile-bytes', feature_count: 5, limit: 5)
      query = instance_double(Points::VectorTileQuery, call: result)
      allow(Points::VectorTileQuery).to receive(:new).and_return(query)

      get path, params: { api_key: user.api_key }

      expect(response).to have_http_status(:ok)
      expect(response.headers['X-Dawarich-Tile-Truncated']).to eq('1')
    end

    it 'accepts bearer authentication' do
      create(:point, user:, longitude: 0.0, latitude: 0.0, lonlat: 'POINT(0 0)')

      get path, headers: { 'Authorization' => "Bearer #{user.api_key}" }

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq('application/vnd.mapbox-vector-tile')
    end

    context 'at zooms that use the geography prefilter' do
      # z=0 skips the prefilter, so the z=0 specs above never reach this branch
      let(:zoomed_path) { '/api/v1/tiles/points/10/544/355.mvt' }

      it 'returns the tile for a point inside the tile' do
        create(:point, user:, longitude: 11.6015, latitude: 48.1503,
                       lonlat: 'POINT(11.6015 48.1503)')

        get zoomed_path, params: { api_key: user.api_key }

        expect(response).to have_http_status(:ok)
        expect(response.body.bytesize).to be_positive
      end

      it 'returns 204 for a tile with no points' do
        create(:point, user:, longitude: 0.0, latitude: 0.0, lonlat: 'POINT(0 0)')

        get zoomed_path, params: { api_key: user.api_key }

        expect(response).to have_http_status(:no_content)
      end

      it 'keeps a point that only falls inside the tile buffer' do
        # Just outside the tile edge but within the MARGIN band, so it must
        # still render rather than clip at the seam
        edge = ActiveRecord::Base.connection.select_one(
          "SELECT ST_X(p) AS lon, ST_Y(p) AS lat FROM (
             SELECT ST_Transform(ST_SetSRID(ST_MakePoint(
               ST_XMin(ST_TileEnvelope(10,544,355)) - 12,
               ST_YMin(ST_TileEnvelope(10,544,355)) + 12), 3857), 4326) AS p) s"
        )
        create(:point, user:, longitude: edge['lon'], latitude: edge['lat'],
                       lonlat: "POINT(#{edge['lon']} #{edge['lat']})")

        get zoomed_path, params: { api_key: user.api_key }

        expect(response).to have_http_status(:ok)
      end
    end

    it 'returns 401 without authentication' do
      get path

      expect(response).to have_http_status(:unauthorized)
    end

    describe 'HTTP caching' do
      let(:range) do
        { start_at: Time.utc(2024, 1, 1).to_i.to_s, end_at: Time.utc(2024, 12, 31).to_i.to_s }
      end
      let(:cached_params) { { api_key: user.api_key, **range } }

      before do
        create(:point, user:, timestamp: Time.utc(2024, 6, 1).to_i,
                       longitude: 0.0, latitude: 0.0, lonlat: 'POINT(0 0)')
      end

      it 'serves cacheable responses and honors conditional revalidation' do
        get path, params: cached_params

        expect(response).to have_http_status(:ok)
        expect(response.headers['Cache-Control']).to eq('max-age=300, private')
        expect(response.headers['Vary']).to include('Authorization')
        etag = response.headers['ETag']
        expect(etag).to be_present

        get path, params: cached_params, headers: { 'If-None-Match' => etag }

        expect(response).to have_http_status(:not_modified)
        expect(response.body).to be_empty
        expect(response.headers['Cache-Control']).to eq('max-age=300, private')
      end

      it 'invalidates on a bump inside the requested range but not outside it' do
        get path, params: cached_params
        etag = response.headers['ETag']

        Points::TileEpoch.bump(user.id, timestamps: [Time.utc(2019, 6, 1).to_i])
        get path, params: cached_params, headers: { 'If-None-Match' => etag }
        expect(response).to have_http_status(:not_modified)

        Points::TileEpoch.bump(user.id, timestamps: [Time.utc(2024, 6, 1).to_i])
        get path, params: cached_params, headers: { 'If-None-Match' => etag }
        expect(response).to have_http_status(:ok)
      end

      it 'gives two users different ETags for the same tile and range' do
        other_user = create(:user)
        create(:point, user: other_user, timestamp: Time.utc(2024, 6, 1).to_i,
                       longitude: 0.0, latitude: 0.0, lonlat: 'POINT(0 0)')

        get path, params: cached_params
        first_etag = response.headers['ETag']

        get path, params: { api_key: other_user.api_key, **range }

        expect(response.headers['ETag']).to be_present
        expect(response.headers['ETag']).not_to eq(first_etag)
      end

      it 'changes the ETag when the plan data window changes, with no point write' do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
        user.update_column(:plan, User.plans[:lite])

        get path, params: cached_params
        lite_etag = response.headers['ETag']

        get path, params: cached_params
        expect(response.headers['ETag']).to eq(lite_etag)

        user.update_column(:plan, User.plans[:pro])
        get path, params: cached_params, headers: { 'If-None-Match' => lite_etag }

        expect(response).to have_http_status(:ok)
      end

      it 'changes the ETag when the tile schema version is bumped' do
        get path, params: cached_params
        etag = response.headers['ETag']

        stub_const('Api::V1::Tiles::PointsController::TILE_SCHEMA_VERSION', 999)
        get path, params: cached_params, headers: { 'If-None-Match' => etag }

        expect(response).to have_http_status(:ok)
      end

      it 'revalidates empty tiles to 304 as well' do
        empty_params = { api_key: user.api_key,
                         start_at: Time.utc(2010, 1, 1).to_i.to_s,
                         end_at: Time.utc(2010, 12, 31).to_i.to_s }

        get path, params: empty_params
        expect(response).to have_http_status(:no_content)
        etag = response.headers['ETag']
        expect(etag).to be_present

        get path, params: empty_params, headers: { 'If-None-Match' => etag }
        expect(response).to have_http_status(:not_modified)
      end

      it 'stays no-store when no range is requested at all' do
        # no-store forbids the browser from storing the response at all, which
        # kills conditional revalidation at the root. (Rack::ETag still stamps
        # an inert weak digest on 200 bodies — irrelevant with nothing stored.)
        get path, params: { api_key: user.api_key }
        expect(response.headers['Cache-Control']).to include('no-store')
        expect(response.headers['Cache-Control']).not_to include('max-age')
      end

      it 'keeps error responses uncacheable even after caching headers were set' do
        query = instance_double(Points::VectorTileQuery)
        allow(Points::VectorTileQuery).to receive(:new).and_return(query)
        allow(query).to receive(:call).and_raise(ActiveRecord::QueryCanceled)

        get path, params: cached_params

        expect(response).to have_http_status(:service_unavailable)
        expect(response.headers['Cache-Control']).to include('no-store')
        expect(response.headers['ETag']).to be_nil
      end

      it 'keeps a 400 with a VALID range uncacheable (rescue undoes expires_in/fresh_when)' do
        get '/api/v1/tiles/points/1/5/0.mvt', params: cached_params

        expect(response).to have_http_status(:bad_request)
        expect(response.headers['Cache-Control']).to include('no-store')
        expect(response.headers['ETag']).to be_nil
      end

      it 'gives different tiles and different ranges different ETags' do
        get path, params: cached_params
        base_etag = response.headers['ETag']

        get '/api/v1/tiles/points/1/0/0.mvt', params: cached_params
        other_tile_etag = response.headers['ETag']

        get path, params: { api_key: user.api_key,
                            start_at: Time.utc(2024, 2, 1).to_i.to_s, end_at: range[:end_at] }
        other_range_etag = response.headers['ETag']

        expect([base_etag, other_tile_etag, other_range_etag].uniq.size).to eq(3)
      end
    end

    it 'excludes anomalous points, matching the classic points layer' do
      create(:point, user:, longitude: 0.0, latitude: 0.0, lonlat: 'POINT(0 0)', anomaly: true)

      get path, params: { api_key: user.api_key }

      expect(response).to have_http_status(:no_content)
    end

    it 'returns 204 when the tile has no points for the current user' do
      create(:point, longitude: 0.0, latitude: 0.0, lonlat: 'POINT(0 0)')

      get path, params: { api_key: user.api_key }

      expect(response).to have_http_status(:no_content)
    end

    it 'applies date filtering' do
      create(:point, user:, timestamp: Time.zone.parse('2024-01-01').to_i,
                             longitude: 0.0, latitude: 0.0, lonlat: 'POINT(0 0)')

      get path, params: {
        api_key: user.api_key,
        start_at: Time.zone.parse('2024-02-01').to_i,
        end_at: Time.zone.parse('2024-02-28').to_i
      }

      expect(response).to have_http_status(:no_content)
    end

    it 'applies plan scoping for Lite users on Cloud' do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
      user.update_column(:plan, User.plans[:lite])
      create(
        :point,
        user:,
        timestamp: (DawarichSettings::LITE_DATA_WINDOW + 1.day).ago.to_i,
        longitude: 0.0,
        latitude: 0.0,
        lonlat: 'POINT(0 0)'
      )

      get path, params: { api_key: user.api_key }

      expect(response).to have_http_status(:no_content)
    end

    context 'when a requested range cannot be honored' do
      it 'rejects a malformed bound instead of silently querying a different window' do
        get path, params: { api_key: user.api_key, start_at: 'garbage',
                            end_at: Time.utc(2024, 12, 31).to_i.to_s }

        expect(response).to have_http_status(:bad_request)
        expect(response.headers['Cache-Control']).to include('no-store')
      end

      it 'rejects a reversed range instead of caching an empty tile for it' do
        create(:point, user:, longitude: 0.0, latitude: 0.0, lonlat: 'POINT(0 0)')

        get path, params: { api_key: user.api_key,
                            start_at: Time.utc(2024, 12, 31).to_i.to_s,
                            end_at: Time.utc(2024, 1, 1).to_i.to_s }

        expect(response).to have_http_status(:bad_request)
        expect(response.headers['Cache-Control']).to include('no-store')
        expect(response.headers['ETag']).to be_nil
      end

      it 'accepts a single-instant range where start equals end' do
        get path, params: { api_key: user.api_key,
                            start_at: Time.utc(2024, 6, 1).to_i.to_s,
                            end_at: Time.utc(2024, 6, 1).to_i.to_s }

        expect(response).not_to have_http_status(:bad_request)
      end

      it 'rejects a half-open range rather than serving an uncacheable scan' do
        get path, params: { api_key: user.api_key, start_at: Time.utc(2024, 1, 1).to_i.to_s }

        expect(response).to have_http_status(:bad_request)
      end

      it 'still serves a request that asks for no range at all' do
        create(:point, user:, longitude: 0.0, latitude: 0.0, lonlat: 'POINT(0 0)')

        get path, params: { api_key: user.api_key }

        expect(response).to have_http_status(:ok)
      end
    end

    it 'returns 400 for invalid tile coordinates' do
      get '/api/v1/tiles/points/1/5/0.mvt', params: { api_key: user.api_key }

      expect(response).to have_http_status(:bad_request)
      expect(JSON.parse(response.body)).to eq('error' => 'Invalid tile coordinates')
    end
  end
end

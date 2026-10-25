# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'A one-day points tile in a dense historical cluster', type: :request do
  it 'reads a bounded number of points and serves the tile before the query timeout' do
    user = create(:user)
    connection = Point.connection
    start_at = 1_500_000_000
    end_at = start_at + 1.day.to_i - 1

    # Entirely synthetic ocean coordinates, derived from an arbitrary Pacific
    # tile. 431k historical points occupy it; only 431 belong to the requested
    # day. The remaining points widen the spatial statistics, as trips would.
    connection.execute(<<~SQL)
      INSERT INTO points (user_id, timestamp, lonlat, created_at, updated_at)
      SELECT #{user.id}, #{start_at} + i * 200,
        CASE WHEN i <= 431000 THEN
          ST_Transform(ST_Translate(ST_Centroid(ST_TileEnvelope(15, 3640, 20000)),
            (i % 101) - 50, ((i / 101) % 101) - 50), 4326)::geography
        ELSE
          ST_SetSRID(ST_MakePoint(-155 + (i % 1000) * 0.03,
            -57 + ((i / 1000) % 200) * 0.07), 4326)::geography
        END,
        NOW(), NOW()
      FROM generate_series(1, 663000) AS i
    SQL
    connection.execute('ANALYZE points')

    scope = user.points.without_raw_data.not_anomaly.where(timestamp: start_at..end_at)
    day_count = scope.count(:all)
    query = Points::VectorTileQuery.new(scope: scope, z: 15, x: 3640, y: 20_000)
    # Measure actual row visits instead of relying solely on wall-clock timing.
    # This also catches the bad plan on machines fast enough to beat the timeout.
    plan = JSON.parse(connection.select_value(
                        "EXPLAIN (ANALYZE, FORMAT JSON) #{query.send(:tile_sql)}"
                      )).first.fetch('Plan')
    pending = [plan]
    visited_points = 0
    until pending.empty?
      node = pending.pop
      pending.concat(node.fetch('Plans', []))
      next unless node['Relation Name'] == 'points'

      visited_points += (node.fetch('Actual Rows') + node.fetch('Rows Removed by Filter', 0)) *
                        node.fetch('Actual Loops')
    end

    # Scale the timeout down for the local PostgreSQL instance: this is still a
    # real database cancellation, with no sleep or mocked query/exception.
    allow(VectorTileTimeout).to receive(:query_timeout_ms).and_return(100)
    # A canceled statement aborts its transaction. Roll back a savepoint after
    # the request so fixture cleanup and the expectations can still run.
    connection.transaction(requires_new: true) do
      get '/api/v1/tiles/points/15/3640/20000.mvt',
          params: { api_key: user.api_key, start_at: start_at, end_at: end_at }
      raise ActiveRecord::Rollback
    end

    aggregate_failures do
      expect(day_count).to eq(431)
      expect(visited_points).to be <= day_count * 10
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq('application/vnd.mapbox-vector-tile')
      expect(response.body.bytesize).to be_positive
    end
  end
end

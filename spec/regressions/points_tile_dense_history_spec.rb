# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'A one-day points tile in a dense historical cluster', type: :request do
  def visited_points(plan)
    pending = [plan]
    visited = 0
    until pending.empty?
      node = pending.pop
      pending.concat(node.fetch('Plans', []))
      next unless node['Relation Name'] == 'points'

      visited += (node.fetch('Actual Rows') + node.fetch('Rows Removed by Filter', 0)) * node.fetch('Actual Loops')
    end
    visited
  end

  it 'reads only the requested day instead of every point in the tile' do
    user = create(:user)
    connection = Point.connection
    start_at = 1_500_000_000
    end_at = start_at + 1.day.to_i - 1

    # Entirely synthetic ocean coordinates, derived from an arbitrary Pacific
    # tile. 20k historical points occupy it; only 431 belong to the requested
    # day. The remaining points widen the spatial statistics, as trips would.
    connection.execute(<<~SQL)
      INSERT INTO points (user_id, timestamp, lonlat, created_at, updated_at)
      SELECT #{user.id}, #{start_at} + i * 200,
        CASE WHEN i <= 20000 THEN
          ST_Transform(ST_Translate(ST_Centroid(ST_TileEnvelope(15, 3640, 20000)),
            (i % 101) - 50, ((i / 101) % 101) - 50), 4326)::geography
        ELSE
          ST_SetSRID(ST_MakePoint(-155 + (i % 1000) * 0.03,
            -57 + ((i / 1000) % 200) * 0.07), 4326)::geography
        END,
        NOW(), NOW()
      FROM generate_series(1, 40000) AS i
    SQL
    connection.execute('ANALYZE points')

    statements = []
    collector = ->(_name, _start, _finish, _id, payload) { statements << payload[:sql] }
    ActiveSupport::Notifications.subscribed(collector, 'sql.active_record') do
      get '/api/v1/tiles/points/15/3640/20000.mvt',
          params: { api_key: user.api_key, start_at: start_at, end_at: end_at }
    end
    tile_sql = statements.find { |sql| sql.include?('ST_AsMVT') }

    # Row visits come from the executed plan, so the check holds on any
    # machine speed rather than depending on the query timeout.
    plan = JSON.parse(connection.select_value("EXPLAIN (ANALYZE, FORMAT JSON) #{tile_sql}")).first.fetch('Plan')
    day_count = user.points.where(timestamp: start_at..end_at).count

    aggregate_failures do
      expect(day_count).to eq(431)
      expect(visited_points(plan)).to be <= day_count * 10
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq('application/vnd.mapbox-vector-tile')
      expect(response.body.bytesize).to be_positive
    end
  end
end

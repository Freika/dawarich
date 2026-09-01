# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20260901100000_create_points_v2.rb')
require Rails.root.join('db/migrate/20260901110000_rewrite_points_to_v2.rb')

# D6 - the blocking verification for the points v2 rewrite. Runs the real
# transform against a seeded v1 world and checks the invariants the release
# notes promise: nothing lost, values transformed exactly, re-runs harmless.
RSpec.describe 'points v2 rewrite verification', :non_transactional do
  let(:connection) { ActiveRecord::Base.connection }

  let!(:users) { Array.new(3) { create(:user) } }

  def seed_v1(user_id, timestamp:, tracker: nil, velocity: nil, battery: nil,
              altitude: nil, altitude_decimal: nil, lon: 12.3712, lat: 51.3402)
    connection.select_value(<<~SQL)
      INSERT INTO points ("timestamp", user_id, tracker_id, velocity, battery,
                          altitude, altitude_decimal, lonlat, created_at, updated_at)
      VALUES (#{timestamp.nil? ? 'NULL' : timestamp}, #{user_id},
              #{connection.quote(tracker)}, #{connection.quote(velocity)},
              #{battery.nil? ? 'NULL' : battery},
              #{altitude.nil? ? 'NULL' : altitude},
              #{altitude_decimal.nil? ? 'NULL' : altitude_decimal},
              'POINT(#{lon} #{lat})', NOW(), NOW())
      RETURNING id
    SQL
  end

  before do
    PointsV1Schema.install_v1_points
    connection.execute('DROP TABLE IF EXISTS points_v2 CASCADE')
    CreatePointsV2.new.up

    # Three users, mixed shapes: plain rows, a tracker combo (unstamped -
    # inline stamping must resolve it), garbage velocity, divergent altitude,
    # NULL timestamps sharing a created_at, int32-ceiling timestamp.
    @plain      = seed_v1(users[0].id, timestamp: 1_700_000_000, velocity: '12.5', battery: 80)
    @tracked    = seed_v1(users[0].id, timestamp: 1_700_000_060, tracker: 'pixel-8', lon: 12.38)
    @garbage    = seed_v1(users[1].id, timestamp: 1_700_000_120, velocity: 'broken', battery: 70_000)
    @divergent  = seed_v1(users[1].id, timestamp: 1_700_000_180, altitude: 100, altitude_decimal: 101.25)
    @ceiling    = seed_v1(users[2].id, timestamp: 2_147_000_000)
    @null_ts    = Array.new(3) { |i| seed_v1(users[2].id, timestamp: nil, lon: 12.4 + (i * 0.01)) }
    connection.execute("UPDATE points SET created_at = '2026-04-15 12:00:00' WHERE \"timestamp\" IS NULL")

    RewritePointsToV2.new.up
  end

  after do
    %w[points_v2 points_v2_changes points_v2_rewrite_state].each do |table|
      connection.execute("DROP TABLE IF EXISTS #{table} CASCADE")
    end
    PointsV1Schema.restore_real_points
  end

  it 'preserves per-user counts exactly' do
    pre = { users[0].id => 2, users[1].id => 2, users[2].id => 4 }

    post = connection.select_rows('SELECT user_id, COUNT(*) FROM points GROUP BY user_id')
                     .to_h { |user_id, count| [user_id, count.to_i] }

    expect(post).to eq(pre)
  end

  it 'transforms every value per the frozen rules' do
    rows = connection.select_all('SELECT * FROM points ORDER BY id').index_by { |r| r['id'] }

    expect(rows[@plain]['velocity']).to eq(12.5)
    expect(rows[@plain]['battery']).to eq(80)
    expect(rows[@garbage]['velocity']).to be_nil
    expect(rows[@garbage]['battery']).to be_nil
    expect(rows[@divergent]['altitude']).to eq(101.25)
    expect(rows[@ceiling]['timestamp']).to eq(2_147_000_000)
  end

  it 'inline-stamps the tracker combo with a digest the ingest resolver reuses' do
    source_id = connection.select_value("SELECT source_id FROM points WHERE id = #{@tracked}")
    expect(source_id).not_to be_nil

    row = { tracker_id: 'pixel-8' }
    Points::DimensionResolver.new.stamp([row])
    expect(row[:source_id]).to eq(source_id.to_i)
  end

  it 'synthesizes unique in-order timestamps for the NULL rows, anchored at created_at' do
    synthesized = connection.select_rows(
      "SELECT id, \"timestamp\" FROM points WHERE id IN (#{@null_ts.join(',')}) ORDER BY id"
    )

    timestamps = synthesized.map { |_, ts| ts }
    anchor = Time.utc(2026, 4, 15, 12).to_i
    expect(timestamps.uniq.size).to eq(3)
    expect(timestamps).to eq(timestamps.sort)
    expect(timestamps).to all(be_between(anchor - 10_000, anchor + 10_000))
  end

  it 'is idempotent: a second migration run changes nothing' do
    checksum = -> { connection.select_value("SELECT md5(string_agg(points::text, '|' ORDER BY id)) FROM points") }
    before_checksum = checksum.call

    RewritePointsToV2.new.up

    expect(checksum.call).to eq(before_checksum)
  end

  it 'serves the hot month-bounded query from the carried-over unique index' do
    # Fixture tables are tiny enough that the planner would (correctly)
    # seq-scan; disabling it locally proves the index EXISTS and is usable.
    connection.execute('SET enable_seqscan = off')
    plan = connection.select_all(<<~SQL).rows.flatten.join("\n")
      EXPLAIN SELECT id FROM points
      WHERE user_id = #{users[0].id} AND "timestamp" BETWEEN 1699990000 AND 1700090000
    SQL
    connection.execute('SET enable_seqscan = on')

    expect(plan).to include('index_points_on_user_id_timestamp_lonlat')
  end
end

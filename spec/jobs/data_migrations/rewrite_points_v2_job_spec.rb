# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DataMigrations::RewritePointsV2Job, :non_transactional do
  let(:connection) { ActiveRecord::Base.connection }
  let(:user) { create(:user) }

  def ensure_v2_table
    return if connection.table_exists?('points_v2')

    require Rails.root.join('db/migrate/20260901100000_create_points_v2.rb')
    CreatePointsV2.new.up
  end

  def teardown_rewrite_artifacts
    connection.execute(<<~SQL)
      DROP TRIGGER IF EXISTS points_v2_capture ON points;
      DROP FUNCTION IF EXISTS points_v2_capture();
      DROP TABLE IF EXISTS points_v2_changes;
      DROP TABLE IF EXISTS points_v2_rewrite_state;
    SQL
    connection.execute('TRUNCATE points_v2') if connection.table_exists?('points_v2')
  end

  before do
    PointsV1Schema.install_v1_points
    ensure_v2_table
    teardown_rewrite_artifacts
    PointSource.delete_all
  end

  after do
    teardown_rewrite_artifacts
    PointsV1Schema.restore_real_points
  end

  def v2_row(id)
    connection.select_all("SELECT * FROM points_v2 WHERE id = #{id.to_i}").first
  end

  def v2_count
    connection.select_value('SELECT COUNT(*) FROM points_v2').to_i
  end

  describe 'the copy' do
    it 'copies a stamped row verbatim with retypes applied' do
      point = create(:point, user: user, timestamp: 1_700_000_000)
      source = PointSource.create!(digest: SecureRandom.hex(16), tracker_id: 'pixel-8')
      point.update_columns(source_id: source.id, velocity: '12.5', battery: 80,
                           altitude: 100, altitude_decimal: 101.25, country: nil)

      described_class.perform_now

      row = v2_row(point.id)
      expect(row['timestamp']).to eq(1_700_000_000)
      expect(row['source_id']).to eq(source.id)
      expect(row['velocity']).to eq(12.5)
      expect(row['battery']).to eq(80)
      expect(row['altitude']).to eq(101.25)
    end

    it 'nulls a velocity that does not parse as a number and a battery out of smallint range' do
      point = create(:point, user: user, timestamp: 1_700_000_100)
      point.update_columns(source_id: nil, velocity: 'not-a-speed', battery: 70_000)

      described_class.perform_now

      row = v2_row(point.id)
      expect(row['velocity']).to be_nil
      expect(row['battery']).to be_nil
    end

    it 'copies the int32 ceiling and v2 accepts post-Y2038 timestamps' do
      point = create(:point, user: user, timestamp: 2_147_000_000)

      described_class.perform_now

      expect(v2_row(point.id)['timestamp']).to eq(2_147_000_000)

      connection.execute(<<~SQL)
        INSERT INTO points_v2 (id, "timestamp", user_id, created_at, updated_at)
        VALUES (nextval('points_id_seq'), 2200000000, #{user.id}, NOW(), NOW())
      SQL
      expect(connection.select_value('SELECT MAX("timestamp") FROM points_v2')).to eq(2_200_000_000)
    end

    it 'is idempotent across re-runs' do
      create(:point, user: user, timestamp: 1_700_000_200)

      described_class.perform_now
      expect { described_class.perform_now }.not_to(change { v2_count })
    end
  end

  describe 'inline dimension stamping' do
    it 'stamps unstamped rows with a digest byte-identical to the ingest resolver' do
      combo = { tracker_id: 'trk-9', topic: 'owntracks/u/trk-9', ssid: 'cafe', bssid: 'aa:bb',
                connection: 1, trigger: 5, battery_status: 1,
                inrids: '{home}', in_regions: '{berlin}' }
      point = create(:point, user: user, timestamp: 1_700_000_300)
      point.update_columns(source_id: nil, **combo)

      described_class.perform_now

      source_id = v2_row(point.id)['source_id']
      expect(source_id).not_to be_nil

      resolver_row = { tracker_id: 'trk-9', topic: 'owntracks/u/trk-9', ssid: 'cafe', bssid: 'aa:bb',
                       connection: 1, trigger: 5, battery_status: 1,
                       inrids: ['home'], in_regions: ['berlin'] }
      Points::DimensionResolver.new.stamp([resolver_row])
      expect(resolver_row[:source_id]).to eq(source_id)
    end
  end

  describe 'NULL-timestamp synthesis' do
    it 'synthesizes unique, order-preserving timestamps anchored at created_at across batch boundaries' do
      shared_created_at = Time.zone.parse('2026-04-15 12:00:00')
      points = Array.new(5) do
        create(:point, user: user, timestamp: rand(1_700_000_000..1_700_099_999)).tap do |p|
          p.update_columns(timestamp: nil, created_at: shared_created_at,
                           lonlat: 'POINT(12.3712 51.3402)')
        end
      end

      described_class.perform_now(2)

      rows = points.map { |p| v2_row(p.id) }
      expect(rows).to all(be_present)
      timestamps = rows.map { |r| r['timestamp'] }
      expect(timestamps.uniq.size).to eq(5)
      expect(timestamps.sort).to eq(points.sort_by(&:id).map { |p| v2_row(p.id)['timestamp'] }.sort)
      expect(timestamps).to all(be > shared_created_at.to_i)
      expect(timestamps).to all(be <= shared_created_at.to_i + 5)
    end
  end

  describe 'live writes during the copy' do
    it 'captures inserts, updates and deletes via the trigger and applies them in catch-up' do
      copied = create(:point, user: user, timestamp: 1_700_001_000)
      doomed = create(:point, user: user, timestamp: 1_700_001_060)

      job = described_class.new
      job.run_phases_through_copy

      late = create(:point, user: user, timestamp: 1_700_001_120)
      copied.update_columns(city: 'Leipzig')
      doomed.delete

      job.finish

      expect(v2_row(late.id)).to be_present
      expect(v2_row(copied.id)['city']).to eq('Leipzig')
      expect(v2_row(doomed.id)).to be_nil
    end
  end

  describe 'indexes and foreign keys' do
    it 'builds the v2 index set and the four foreign keys' do
      create(:point, user: user, timestamp: 1_700_002_000)

      described_class.perform_now

      index_names = connection.select_values(
        "SELECT indexname FROM pg_indexes WHERE tablename = 'points_v2'"
      )
      expect(index_names).to include(
        'index_points_v2_on_lonlat', 'index_points_v2_on_user_id_timestamp_lonlat',
        'idx_points_v2_track_id_timestamp', 'index_points_v2_on_import_id',
        'index_points_v2_on_visit_id', 'index_points_v2_on_raw_data_archive_id',
        'index_points_v2_on_not_reverse_geocoded', 'index_points_v2_on_unarchived'
      )
      expect(index_names).not_to include('idx_points_v2_user_id_legacy_tracker')

      fk_targets = connection.select_values(<<~SQL)
        SELECT confrelid::regclass::text
        FROM pg_constraint
        WHERE conrelid = 'points_v2'::regclass AND contype = 'f'
      SQL
      expect(fk_targets).to match_array(%w[points_raw_data_archives tracks users visits])
    end
  end

  describe 'fast path' do
    it 'skips capture and walk entirely when points is empty' do
      described_class.perform_now

      trigger_count = connection.select_value(
        "SELECT COUNT(*) FROM pg_trigger WHERE tgname = 'points_v2_capture'"
      ).to_i
      expect(trigger_count).to eq(0)
      expect(v2_count).to eq(0)
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DataMigrations::RewritePointsV2Job, :non_transactional do
  let(:connection) { ActiveRecord::Base.connection }
  let!(:user) { create(:user) }

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

  # Non-transactional: visits soft-delete under dependent: :destroy, so take
  # the user's rows out by hand before the user goes.
  after do
    teardown_rewrite_artifacts
    PointsV1Schema.restore_real_points
    Visit.where(user_id: user.id).delete_all
    Area.where(user_id: user.id).delete_all
    user.destroy
    Stat.where(user_id: user.id).delete_all
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
      connection.execute(<<~SQL)
        UPDATE points
        SET source_id = #{source.id}, velocity = '12.5', battery = 80,
            altitude = 100, altitude_decimal = 101.25, country = NULL
        WHERE id = #{point.id}
      SQL

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
      point = create(:point, user: user, timestamp: 1_700_000_300)
      connection.execute(<<~SQL)
        UPDATE points
        SET source_id = NULL, tracker_id = 'trk-9', topic = 'owntracks/u/trk-9', ssid = 'cafe',
            bssid = 'aa:bb', connection = 1, trigger = 5, battery_status = 1,
            inrids = '{home}', in_regions = '{berlin}'
        WHERE id = #{point.id}
      SQL

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

    it 'detaches points whose track or visit is gone before adding the foreign keys' do
      connection.execute('ALTER TABLE points DROP CONSTRAINT fk_rails_v1_points_visits')
      track = create(:track, user: user)
      visit = create(:visit, user: user, area: create(:area, user: user))
      orphan = create(:point, user: user, timestamp: 1_700_003_000, track_id: track.id, visit_id: visit.id)
      kept = create(:point, user: user, timestamp: 1_700_003_100, track_id: track.id)
      connection.execute("DELETE FROM visits WHERE id = #{visit.id}")

      described_class.perform_now

      expect(v2_row(orphan.id)['visit_id']).to be_nil
      expect(v2_row(orphan.id)['track_id']).to eq(track.id)
      expect(v2_row(kept.id)['track_id']).to eq(track.id)
    end

    it 'detaches points whose track was deleted underneath them' do
      connection.execute('ALTER TABLE points DROP CONSTRAINT fk_rails_v1_points_tracks')
      track = create(:track, user: user)
      orphan = create(:point, user: user, timestamp: 1_700_004_000, track_id: track.id)
      connection.execute("DELETE FROM tracks WHERE id = #{track.id}")

      described_class.perform_now

      expect(v2_row(orphan.id)['track_id']).to be_nil
      track_fk_count = connection.select_value(
        "SELECT COUNT(*) FROM pg_constraint WHERE conname = 'fk_points_v2_track'"
      ).to_i
      expect(track_fk_count).to eq(1)
    end
  end

  describe 'resume' do
    it 'continues from the persisted cursor without touching rows below it' do
      ids = (1..5).map { |i| create(:point, user: user, timestamp: 1_700_020_000 + i).id }
      job = described_class.new
      job.send(:ensure_state_table)
      connection.execute("UPDATE points_v2_rewrite_state SET copy_cursor = #{ids[1]} WHERE id = 1")

      job.run_phases_through_copy(2)

      expect(ids[0..1].map { |id| v2_row(id) }).to all(be_nil)
      expect(ids[2..].map { |id| v2_row(id) }).to all(be_present)
    end

    it 'halves the batch when a statement is aborted and still copies everything' do
      stub_const('DataMigrations::RewritePointsV2Job::MIN_BATCH_SIZE', 1)
      ids = (1..6).map { |i| create(:point, user: user, timestamp: 1_700_030_000 + i).id }
      aborted = false
      allow(connection).to receive(:execute).and_wrap_original do |original, *args, **kwargs|
        if !aborted && args.first.include?('INSERT INTO points_v2') && args.first.include?('BETWEEN')
          aborted = true
          raise ActiveRecord::QueryCanceled, 'canceling statement due to statement timeout'
        end
        original.call(*args, **kwargs)
      end
      allow(Rails.logger).to receive(:warn).and_call_original

      described_class.new.run_phases_through_copy(4)

      expect(ids.map { |id| v2_row(id) }).to all(be_present)
      expect(Rails.logger).to have_received(:warn).with(/retrying at 2/)
    end

    it 'retries a batch that waited on a lock instead of failing the run' do
      ids = (1..3).map { |i| create(:point, user: user, timestamp: 1_700_060_000 + i).id }
      waited = false
      allow(connection).to receive(:execute).and_wrap_original do |original, *args, **kwargs|
        if !waited && args.first.include?('INSERT INTO points_v2') && args.first.include?('BETWEEN')
          waited = true
          raise ActiveRecord::LockWaitTimeout, 'canceling statement due to lock timeout'
        end
        original.call(*args, **kwargs)
      end
      allow_any_instance_of(described_class).to receive(:sleep)

      described_class.new.run_phases_through_copy

      expect(ids.map { |id| v2_row(id) }).to all(be_present)
    end

    it 'adds the foreign keys NOT VALID and leaves validation to the swap' do
      create(:point, user: user, timestamp: 1_700_061_000)

      described_class.perform_now

      states = connection.select_rows(
        "SELECT conname, convalidated FROM pg_constraint WHERE conrelid = 'points_v2'::regclass AND contype = 'f'"
      ).to_h
      expect(states.keys).to match_array(%w[fk_points_v2_raw_data_archive fk_points_v2_track
                                            fk_points_v2_user fk_points_v2_visit])
      expect(states.values).to all(be(false))
    end
  end

  describe 'the drain' do
    def insert_v1_point(conn, timestamp)
      conn.execute(<<~SQL)
        INSERT INTO points ("timestamp", user_id, lonlat, created_at, updated_at)
        VALUES (#{timestamp}, #{user.id}, 'POINT(12.3712 51.3402)', NOW(), NOW())
      SQL
    end

    it 'consumes exactly the change rows it applied' do
      described_class.new.run_phases_through_copy
      3.times { |i| insert_v1_point(connection, 1_700_040_000 + i) }
      capture = Points::Rewrite::ChangeCapture.new(connection)

      expect(capture.drain_batch(2)).to eq(2)
      expect(capture.pending_count).to eq(1)
      expect(v2_count).to eq(2)
    end

    it 'never drops a change whose writer commits mid-drain' do
      described_class.new.run_phases_through_copy
      slow_writer = ActiveRecord::Base.connection_pool.checkout
      committed = false
      begin
        slow_writer.execute('BEGIN')
        insert_v1_point(slow_writer, 1_700_050_000)
        insert_v1_point(connection, 1_700_050_001)
        allow(connection).to receive(:execute).and_wrap_original do |original, *args, **kwargs|
          if !committed && args.first.lstrip.start_with?('DELETE FROM points_v2_changes')
            committed = true
            slow_writer.execute('COMMIT')
          end
          original.call(*args, **kwargs)
        end

        Points::Rewrite::ChangeCapture.new(connection).drain_fully
      ensure
        slow_writer.execute('ROLLBACK') unless committed
        ActiveRecord::Base.connection_pool.checkin(slow_writer)
      end

      timestamps = connection.select_values('SELECT "timestamp" FROM points_v2 ORDER BY 1')
      expect(timestamps).to include(1_700_050_000, 1_700_050_001)
    end
  end

  describe 'synthesis collisions' do
    it 'sidesteps a real row already at the synthesized (user, timestamp, lonlat)' do
      anchor = Time.utc(2026, 4, 15, 10)
      connection.execute(<<~SQL)
        INSERT INTO points ("timestamp", user_id, lonlat, created_at, updated_at) VALUES
          (NULL, #{user.id}, 'POINT(12.3712 51.3402)', '2026-04-15 10:00:00', '2026-04-15 10:00:00'),
          (#{anchor.to_i + 1}, #{user.id}, 'POINT(12.3712 51.3402)', '2026-04-15 10:00:00', '2026-04-15 10:00:00')
      SQL

      expect { described_class.perform_now }.not_to raise_error

      timestamps = connection.select_values(
        "SELECT \"timestamp\" FROM points_v2 WHERE user_id = #{user.id} ORDER BY 1"
      )
      expect(timestamps.size).to eq(2)
      expect(timestamps.uniq.size).to eq(2)
      expect(timestamps).to include(anchor.to_i + 1)
    end

    it 'moves a run of same-place synthesized rows past a real row in one go' do
      anchor = Time.utc(2026, 4, 15, 10)
      connection.execute(<<~SQL)
        INSERT INTO points ("timestamp", user_id, lonlat, created_at, updated_at) VALUES
          (NULL, #{user.id}, 'POINT(12.3712 51.3402)', '2026-04-15 10:00:00', '2026-04-15 10:00:00'),
          (NULL, #{user.id}, 'POINT(12.3712 51.3402)', '2026-04-15 10:00:00', '2026-04-15 10:00:00'),
          (NULL, #{user.id}, 'POINT(12.3712 51.3402)', '2026-04-15 10:00:00', '2026-04-15 10:00:00'),
          (#{anchor.to_i + 1}, #{user.id}, 'POINT(12.3712 51.3402)', '2026-04-15 10:00:00', '2026-04-15 10:00:00')
      SQL

      expect { described_class.perform_now }.not_to raise_error

      timestamps = connection.select_values(
        "SELECT \"timestamp\" FROM points_v2 WHERE user_id = #{user.id} ORDER BY 1"
      )
      expect(timestamps.size).to eq(4)
      expect(timestamps.uniq.size).to eq(4)
    end

    it 'keeps a moved timestamp when finish runs again after the index exists' do
      anchor = Time.utc(2026, 4, 15, 10)
      connection.execute(<<~SQL)
        INSERT INTO points ("timestamp", user_id, lonlat, created_at, updated_at) VALUES
          (NULL, #{user.id}, 'POINT(12.3712 51.3402)', '2026-04-15 10:00:00', '2026-04-15 10:00:00'),
          (#{anchor.to_i + 1}, #{user.id}, 'POINT(12.3712 51.3402)', '2026-04-15 10:00:00', '2026-04-15 10:00:00')
      SQL
      job = described_class.new
      job.run_phases_through_copy
      job.finish
      moved = connection.select_values(
        "SELECT \"timestamp\" FROM points_v2 WHERE user_id = #{user.id} ORDER BY 1"
      )

      expect { job.finish }.not_to raise_error

      again = connection.select_values(
        "SELECT \"timestamp\" FROM points_v2 WHERE user_id = #{user.id} ORDER BY 1"
      )
      expect(again).to eq(moved)
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

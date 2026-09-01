# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20260901100000_create_points_v2.rb')
require Rails.root.join('db/migrate/20260901110000_rewrite_points_to_v2.rb')

RSpec.describe RewritePointsToV2, :non_transactional do
  subject(:migration) { described_class.new }

  let(:connection) { ActiveRecord::Base.connection }
  let(:user) { create(:user) }

  before do
    PointsV1Schema.install_v1_points
    connection.execute('DROP TABLE IF EXISTS points_v2 CASCADE')
    CreatePointsV2.new.up
  end

  after do
    %w[points_v2 points_v2_changes points_v2_rewrite_state].each do |table|
      connection.execute("DROP TABLE IF EXISTS #{table} CASCADE")
    end
    connection.execute('DROP TRIGGER IF EXISTS points_v2_capture ON points')
    connection.execute('DROP FUNCTION IF EXISTS points_v2_capture()')
    PointsV1Schema.restore_real_points
  end

  def seed_v1_point(timestamp:, city: nil)
    connection.select_value(<<~SQL)
      INSERT INTO points ("timestamp", user_id, city, lonlat, created_at, updated_at)
      VALUES (#{timestamp}, #{user.id}, #{connection.quote(city)},
              'POINT(12.3712 51.3402)', NOW(), NOW())
      RETURNING id
    SQL
  end

  it 'swaps points to the v2 shape and keeps the old table as points_legacy_d' do
    seed_v1_point(timestamp: 1_700_000_000, city: 'Leipzig')

    migration.up

    expect(connection.column_exists?(:points, :country_name)).to be(false)
    expect(connection.select_value(%(SELECT "timestamp" FROM points LIMIT 1))).to eq(1_700_000_000)
    expect(connection.table_exists?('points_legacy_d')).to be(true)
    expect(connection.select_value('SELECT COUNT(*) FROM points_legacy_d').to_i).to eq(1)
  end

  it 'renames the v2 indexes and constraints to their canonical v1 names' do
    seed_v1_point(timestamp: 1_700_000_100)

    migration.up

    names = connection.select_values("SELECT indexname FROM pg_indexes WHERE tablename = 'points'")
    expect(names).to include('points_pkey', 'index_points_on_lonlat',
                             'index_points_on_user_id_timestamp_lonlat',
                             'idx_points_track_id_timestamp', 'index_points_on_unarchived')
    expect(names.grep(/_v2/)).to be_empty

    fk_names = connection.select_values(<<~SQL)
      SELECT conname FROM pg_constraint
      WHERE conrelid = 'points'::regclass AND contype = 'f'
    SQL
    expect(fk_names).to match_array(%w[fk_points_raw_data_archive fk_points_track
                                       fk_points_user fk_points_visit])
  end

  it 'moves the sequence so post-swap inserts keep working' do
    seed_v1_point(timestamp: 1_700_000_200)

    migration.up

    new_id = connection.select_value(<<~SQL)
      INSERT INTO points (id, "timestamp", user_id, created_at, updated_at)
      VALUES (nextval('points_id_seq'), 2200000000, #{user.id}, NOW(), NOW())
      RETURNING id
    SQL
    expect(new_id).to be_present
  end

  it 'applies writes that raced the copy before renaming' do
    copied = seed_v1_point(timestamp: 1_700_000_300)

    job = DataMigrations::RewritePointsV2Job.new
    job.run_phases_through_copy
    job.finish
    late = seed_v1_point(timestamp: 1_700_000_360)
    connection.execute("UPDATE points SET city = 'Leipzig' WHERE id = #{copied}")

    migration.up

    expect(connection.select_value("SELECT city FROM points WHERE id = #{copied}")).to eq('Leipzig')
    expect(connection.select_value("SELECT COUNT(*) FROM points WHERE id = #{late}").to_i).to eq(1)
  end

  it 'leaves no rewrite machinery behind' do
    seed_v1_point(timestamp: 1_700_000_400)

    migration.up

    expect(connection.table_exists?('points_v2')).to be(false)
    expect(connection.table_exists?('points_v2_changes')).to be(false)
    expect(connection.table_exists?('points_v2_rewrite_state')).to be(false)
    expect(connection.select_value(
      "SELECT COUNT(*) FROM pg_trigger WHERE tgname = 'points_v2_capture'"
    ).to_i).to eq(0)
  end

  it 'retries the swap after a deadlock with visit or track creation' do
    seed_v1_point(timestamp: 1_700_000_450)
    deadlocked = false
    allow(migration).to receive(:sleep)
    allow_any_instance_of(Points::Rewrite::SchemaSteps).to receive(:add_foreign_keys).and_wrap_original do |m, *a, **kw|
      unless deadlocked
        deadlocked = true
        raise ActiveRecord::Deadlocked, 'PG::TRDeadlockDetected: ERROR:  deadlock detected'
      end
      m.call(*a, **kw)
    end

    expect { migration.up }.not_to raise_error

    expect(deadlocked).to be(true)
    expect(connection.column_exists?(:points, :country_name)).to be(false)
    fk_names = connection.select_values(
      "SELECT conname FROM pg_constraint WHERE conrelid = 'points'::regclass AND contype = 'f'"
    )
    expect(fk_names).to match_array(%w[fk_points_raw_data_archive fk_points_track fk_points_user fk_points_visit])
  end

  it 'is a no-op on second run' do
    seed_v1_point(timestamp: 1_700_000_500)
    migration.up

    expect { migration.up }.not_to raise_error
    expect(connection.select_value('SELECT COUNT(*) FROM points').to_i).to eq(1)
  end

  it 'swaps instantly on an empty database (fresh install)' do
    migration.up

    expect(connection.column_exists?(:points, :country_name)).to be(false)
    expect(connection.select_value('SELECT COUNT(*) FROM points').to_i).to eq(0)
  end

  it 'restores the v1 table on down' do
    seed_v1_point(timestamp: 1_700_000_600)
    migration.up

    migration.down

    expect(connection.column_exists?(:points, :country_name)).to be(true)
    expect(connection.select_value('SELECT COUNT(*) FROM points').to_i).to eq(1)
  end

  it 'leaves points v2-shaped with one foreign key per column after up, down, up' do
    seed_v1_point(timestamp: 1_700_000_650)
    migration.up
    migration.down

    expect { migration.up }.not_to raise_error

    expect(connection.column_exists?(:points, :country_name)).to be(false)
    fk_columns = connection.select_values(<<~SQL)
      SELECT a.attname FROM pg_constraint c
      JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = ANY (c.conkey)
      WHERE c.conrelid = 'points'::regclass AND c.contype = 'f'
    SQL
    expect(fk_columns).to match_array(%w[raw_data_archive_id track_id user_id visit_id])
  end

  it 'lets a rolled-back instance delete tracks and keeps referential integrity on v1' do
    track = create(:track, user: user)
    connection.execute(<<~SQL)
      INSERT INTO points ("timestamp", user_id, track_id, lonlat, created_at, updated_at)
      VALUES (1700000670, #{user.id}, #{track.id}, 'POINT(12.3712 51.3402)', NOW(), NOW())
    SQL
    migration.up
    migration.down

    v2_fks = connection.select_value(
      "SELECT COUNT(*) FROM pg_constraint WHERE conrelid = 'points_v2'::regclass AND contype = 'f'"
    ).to_i
    v1_fk_targets = connection.select_values(
      "SELECT confrelid::regclass::text FROM pg_constraint WHERE conrelid = 'points'::regclass AND contype = 'f'"
    )
    expect(v2_fks).to eq(0)
    expect(v1_fk_targets).to match_array(%w[points_raw_data_archives tracks users visits])
    expect(connection.select_value('SELECT COUNT(*) FROM points_v2').to_i).to eq(0)
    expect { Track.find(track.id).destroy! }.not_to raise_error
    expect(connection.select_value('SELECT track_id FROM points WHERE "timestamp" = 1700000670')).to be_nil
  end

  it 'resumes a rollback whose key re-add timed out' do
    seed_v1_point(timestamp: 1_700_000_675)
    migration.up
    allow_any_instance_of(Points::Rewrite::SchemaSteps).to receive(:sleep)
    allow(connection).to receive(:execute).and_wrap_original do |original, *args, **kwargs|
      raise ActiveRecord::LockWaitTimeout, 'lock timeout' if args.first.include?('fk_points_v1_visit')

      original.call(*args, **kwargs)
    end

    expect { migration.down }.to raise_error(ActiveRecord::LockWaitTimeout)
    expect(connection.column_exists?(:points, :country_name)).to be(true)

    allow(connection).to receive(:execute).and_call_original
    expect { migration.down }.not_to raise_error

    v1_fk_targets = connection.select_values(
      "SELECT confrelid::regclass::text FROM pg_constraint WHERE conrelid = 'points'::regclass AND contype = 'f'"
    )
    expect(v1_fk_targets).to match_array(%w[points_raw_data_archives tracks users visits])
  end

  it 'repairs the keys on the next migrate when a rollback failed before the rename' do
    seed_v1_point(timestamp: 1_700_000_676)
    migration.up
    allow(migration).to receive(:sleep)
    allow(connection).to receive(:execute).and_wrap_original do |original, *args, **kwargs|
      if args.first.include?('ALTER TABLE points RENAME TO points_v2')
        raise ActiveRecord::LockWaitTimeout, 'lock timeout'
      end

      original.call(*args, **kwargs)
    end

    expect { migration.down }.to raise_error(ActiveRecord::LockWaitTimeout)
    expect(connection.column_exists?(:points, :country_name)).to be(false)

    allow(connection).to receive(:execute).and_call_original
    expect { migration.up }.not_to raise_error

    states = connection.select_rows(
      "SELECT conname, convalidated FROM pg_constraint WHERE conrelid = 'points'::regclass AND contype = 'f'"
    ).to_h
    expect(states.keys).to match_array(%w[fk_points_raw_data_archive fk_points_track fk_points_user fk_points_visit])
    expect(states.values).to all(be(true))
  end

  it 'validates the foreign keys after the swap even when a parent vanished during the copy' do
    track = create(:track, user: user)
    connection.execute(<<~SQL)
      INSERT INTO points ("timestamp", user_id, track_id, lonlat, created_at, updated_at)
      VALUES (1700000680, #{user.id}, #{track.id}, 'POINT(12.3712 51.3402)', NOW(), NOW())
    SQL
    DataMigrations::RewritePointsV2Job.new.run_phases_through_copy
    Track.find(track.id).destroy!

    expect { migration.up }.not_to raise_error

    expect(connection.select_value('SELECT track_id FROM points WHERE "timestamp" = 1700000680')).to be_nil
    unvalidated = connection.select_value(
      "SELECT COUNT(*) FROM pg_constraint WHERE conrelid = 'points'::regclass AND contype = 'f' AND NOT convalidated"
    ).to_i
    expect(unvalidated).to eq(0)
  end

  it 'finishes an interrupted validation on the next boot' do
    seed_v1_point(timestamp: 1_700_000_690)
    migration.up
    connection.execute(<<~SQL)
      ALTER TABLE points DROP CONSTRAINT fk_points_user;
      ALTER TABLE points ADD CONSTRAINT fk_points_user FOREIGN KEY (user_id) REFERENCES users(id) NOT VALID;
    SQL

    migration.up

    validated = connection.select_value(
      "SELECT convalidated FROM pg_constraint WHERE conrelid = 'points'::regclass AND conname = 'fk_points_user'"
    )
    expect(validated).to be(true)
  end

  it 'drops the legacy table\'s foreign keys so parents can be deleted during the retention window' do
    track = create(:track, user: user)
    connection.execute(<<~SQL)
      INSERT INTO points ("timestamp", user_id, track_id, lonlat, created_at, updated_at)
      VALUES (1700000660, #{user.id}, #{track.id}, 'POINT(12.3712 51.3402)', NOW(), NOW())
    SQL

    migration.up

    legacy_fks = connection.select_value(
      "SELECT COUNT(*) FROM pg_constraint WHERE conrelid = 'points_legacy_d'::regclass AND contype = 'f'"
    ).to_i
    expect(legacy_fks).to eq(0)

    connection.execute("UPDATE points SET track_id = NULL WHERE track_id = #{track.id}")
    expect { connection.execute("DELETE FROM tracks WHERE id = #{track.id}") }.not_to raise_error
  end

  it 'lands a write that blocked on the swap lock in the new table', threads: 2 do
    seed_v1_point(timestamp: 1_700_000_700)
    locked = Queue.new
    writer_blocked = false
    allow(migration).to receive(:lock_points!).and_wrap_original do |original, *args|
      original.call(*args)
      locked << true
      50.times do
        break if writer_blocked

        writer_blocked = connection.select_value(<<~SQL).to_i.positive?
          SELECT COUNT(*) FROM pg_stat_activity
          WHERE wait_event_type = 'Lock' AND query LIKE 'INSERT INTO points%'
        SQL
        sleep 0.1
      end
    end
    writer = Thread.new do
      locked.pop
      ActiveRecord::Base.connection_pool.with_connection do |writer_connection|
        writer_connection.execute(<<~SQL)
          INSERT INTO points ("timestamp", user_id, lonlat, created_at, updated_at)
          VALUES (1700000800, #{user.id}, 'POINT(12.3712 51.3402)', NOW(), NOW())
        SQL
      end
    end

    migration.up
    writer.join

    expect(writer_blocked).to be(true)
    expect(connection.select_value('SELECT COUNT(*) FROM points WHERE "timestamp" = 1700000800').to_i).to eq(1)
    expect(connection.select_value('SELECT COUNT(*) FROM points_legacy_d WHERE "timestamp" = 1700000800').to_i)
      .to eq(0)
  end

  it 'nulls references whose parent vanished when v1 carried no such key, then validates' do
    connection.execute('ALTER TABLE points DROP CONSTRAINT fk_rails_v1_points_tracks')
    connection.execute('ALTER TABLE points DROP CONSTRAINT fk_rails_v1_points_visits')
    track = create(:track, user: user)
    visit = create(:visit, user: user, area: create(:area, user: user))
    connection.execute(<<~SQL)
      INSERT INTO points ("timestamp", user_id, track_id, visit_id, lonlat, created_at, updated_at)
      VALUES (1700000710, #{user.id}, #{track.id}, #{visit.id}, 'POINT(12.3712 51.3402)', NOW(), NOW())
    SQL
    connection.execute("DELETE FROM tracks WHERE id = #{track.id}")
    connection.execute("DELETE FROM visits WHERE id = #{visit.id}")

    expect { migration.up }.not_to raise_error

    row = connection.select_one('SELECT track_id, visit_id FROM points WHERE "timestamp" = 1700000710')
    expect(row.values).to all(be_nil)
    unvalidated = connection.select_value(
      "SELECT COUNT(*) FROM pg_constraint WHERE conrelid = 'points'::regclass AND contype = 'f' AND NOT convalidated"
    ).to_i
    expect(unvalidated).to eq(0)
  end

  it 'survives an orphan row that is updated during the copy window on a v1 without the key' do
    connection.execute('ALTER TABLE points DROP CONSTRAINT fk_rails_v1_points_tracks')
    track = create(:track, user: user)
    orphan_id = connection.select_value(<<~SQL)
      INSERT INTO points ("timestamp", user_id, track_id, lonlat, created_at, updated_at)
      VALUES (1700000720, #{user.id}, #{track.id}, 'POINT(12.3712 51.3402)', NOW(), NOW())
      RETURNING id
    SQL
    connection.execute("DELETE FROM tracks WHERE id = #{track.id}")
    DataMigrations::RewritePointsV2Job.new.run_phases_through_copy
    connection.execute("UPDATE points SET city = 'Leipzig' WHERE id = #{orphan_id}")

    expect { migration.up }.not_to raise_error

    row = connection.select_one("SELECT track_id, city FROM points WHERE id = #{orphan_id}")
    expect(row['track_id']).to be_nil
    expect(row['city']).to eq('Leipzig')
  end

  it 'logs the row estimate and the expected duration before starting' do
    seed_v1_point(timestamp: 1_700_000_900)
    connection.execute('ANALYZE points')
    allow(Rails.logger).to receive(:info).and_call_original

    migration.up

    expect(Rails.logger).to have_received(:info).with(/rewriting points.*~1 rows.*expect roughly/)
  end
end

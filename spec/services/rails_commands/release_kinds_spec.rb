# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RailsCommands::Registry, 'release reverse-outbox kinds' do
  let(:run_at) { 1.hour.from_now.to_i }

  it 'release_reclassify_tracks enqueues one ReclassifyTrackJob per track at run_at' do
    handler = described_class.handler('release_reclassify_tracks')

    expect { handler.call({ 'user_id' => 7, 'track_ids' => [3, 4], 'run_at' => run_at }) }
      .to have_enqueued_job(TransportationModes::ReclassifyTrackJob).with(3).at(Time.zone.at(run_at))
      .and have_enqueued_job(TransportationModes::ReclassifyTrackJob).with(4).at(Time.zone.at(run_at))
  end

  it 'release_user_redetect enqueues UserRedetectJob at run_at' do
    handler = described_class.handler('release_user_redetect')

    expect { handler.call({ 'user_id' => 7, 'run_at' => run_at }) }
      .to have_enqueued_job(Visits::UserRedetectJob).with(7).at(Time.zone.at(run_at))
  end

  it 'release_null_island_follow_up replays the follow-up' do
    handler = described_class.handler('release_null_island_follow_up')
    user = create(:user)
    track = create(:track, user:)
    timestamp = Time.utc(2026, 3, 5, 12).to_i
    create(:point, user:, track:, longitude: 0.01, latitude: 0.01, timestamp:, anomaly: true)
    visit = create(:visit, user:, place: create(:place, latitude: 0.02, longitude: 0.02, lonlat: 'POINT(0.02 0.02)'))
    allow(Points::TileEpoch).to receive(:bump).and_call_original

    expect { handler.call({ 'user_id' => user.id }) }
      .to have_enqueued_job(Stats::CalculatingJob).with(user.id, 2026, 3)
      .and have_enqueued_job(Tracks::RecalculateJob).with(track.id)
    expect(Visit.exists?(visit.id)).to be(false)
    expect(Points::TileEpoch).to have_received(:bump).with(user.id, timestamps: [timestamp])
  end

  it 'release_null_island_follow_up skips a missing user' do
    handler = described_class.handler('release_null_island_follow_up')

    expect { handler.call({ 'user_id' => 0 }) }.not_to have_enqueued_job
  end
end

RSpec.describe 'A12rel reverse handoff', :eval do
  self.use_transactional_tests = false

  def a12rel_sql(statement, *values)
    result = ActiveRecord::Base.connection.exec_query(
      ActiveRecord::Base.sanitize_sql_array([statement, *values])
    ).to_a
    result.each { |row| row['payload'] = JSON.parse(row['payload']) if row['payload'].is_a?(String) }
    result
  end

  it 'A12rel handoff consumes actual bulk and leaf rows with stable root identity' do
    expect(ActiveRecord::Base.connection_db_config.database).to eq('dawarich_phoenix_test_a12rel_scratch')
    ids = [54_901, 54_902]
    kinds = %w[release_achievements_bulk_check achievements.bulk_check_leaf]
    keys = %w[command:achievements.bulk_check command:achievements.check cron:achievements_bulk_check_job]
    owners = a12rel_sql('SELECT * FROM phoenix.job_owners WHERE key IN (?)', keys)
    sequences = %w[users_id_seq points_id_seq phoenix.rails_commands_id_seq].index_with do |sequence|
      a12rel_sql("SELECT last_value,is_called FROM #{sequence}").sole
    end
    actual = a12rel_sql('SELECT id,kind,payload FROM phoenix.rails_commands WHERE kind IN (?) ORDER BY id', kinds)
    expect(actual.map { _1.fetch('kind') }).to eq([kinds.first, kinds.last, kinds.last])
    due = Time.utc(2026, 10, 4, 12)
    job_id = '2ce791c6-a6d3-57d0-a80b-f180c7944093'
    root = 'e18e8b6f-370a-5f22-a306-3291938cd8c5'
    leaf_root = '00000000-0000-4000-8000-000000549001'
    options = { 'notify' => false, 'force' => true, 'stale_only' => true }
    expect(actual.first.fetch('payload')).to eq('job_id' => job_id, 'options' => options,
                                                'run_at' => '2026-10-04T12:00:00.000000Z')
    sentinels = a12rel_sql("SELECT * FROM phoenix.job_owners WHERE key='cron:achievements_bulk_check_job'")
    users = User.unscoped.where(id: ids).order(:id).map(&:attributes)
    job_owner!('command:achievements.bulk_check', 'sidekiq')
    handler = RailsCommands::Registry.handler(kinds.first)
    expect { handler.call(actual.first.fetch('payload')) }
      .to have_enqueued_job(Achievements::BulkCheckJob).with(**options.symbolize_keys).at(due)
    serialized = ActiveJob::Base.queue_adapter.enqueued_jobs.find { _1['job_id'] == job_id }
    expect(serialized).to be_present
    expect(serialized.fetch('arguments').sole.except('_aj_ruby2_keywords')).to eq(options)
    expect(serialized.fetch('arguments').sole.fetch('_aj_ruby2_keywords').sort).to eq(options.keys.sort)
    job_owner!('command:achievements.bulk_check', 'oban')
    ActiveJob::Base.deserialize(serialized).perform_now
    command = JobOutbox.find(root)
    expect(command.command_type).to eq('achievements.bulk_check')
    expect(command.payload).to eq(options)
    actual.drop(1).zip(ids).each do |row, id|
      event = Digest::UUID.uuid_v5(leaf_root, "check:#{id}")
      expect(row.fetch('payload')).to eq('user_id' => id, 'notify' => false,
                                         'run_at' => '2026-10-04T12:00:00.000000Z', 'event_id' => event)
      leaf = RailsCommands::Registry.handler(kinds.last)
      job_owner!('command:achievements.check', 'sidekiq')
      expect { leaf.call(row.fetch('payload')) }
        .to have_enqueued_job(Achievements::CheckJob).with(id, notify: false, force: false).at(due)
      job_owner!('command:achievements.check', 'oban')
      leaf.call(row.fetch('payload'))
      expect(JobOutbox.find(event).attributes.slice('command_type', 'payload', 'scheduled_at')).to eq(
        'command_type' => 'achievements.check', 'payload' => { 'user_id' => id, 'notify' => false,
                                                            'oldest_timestamp' => nil }, 'scheduled_at' => due
      )
    end
    expect(a12rel_sql("SELECT * FROM phoenix.job_owners WHERE key='cron:achievements_bulk_check_job'")).to eq(sentinels)
    expect(User.unscoped.where(id: ids).order(:id).map(&:attributes)).to eq(users)
  ensure
    if sequences
      a12rel_sql('DELETE FROM phoenix.rails_commands WHERE id IN (?)', actual.map { _1.fetch('id') }) if actual.any?
      JobOutbox.where(event_id: [root, *ids.map { Digest::UUID.uuid_v5(leaf_root, "check:#{_1}") }]).delete_all if root
      if leaf_root
        receipts = ids.map { Digest::UUID.uuid_v5(leaf_root, "scheduled:#{_1}") }
        a12rel_sql('DELETE FROM phoenix.processed_commands WHERE event_id IN (?)',
                   [leaf_root, '00000000-0000-4000-8000-000000540001', *receipts])
      end
      Point.where(user_id: ids).delete_all
      User.unscoped.where(id: ids).delete_all
      a12rel_sql('DELETE FROM phoenix.job_owners WHERE key IN (?)', keys)
      owners.each do |owner|
        connection = ActiveRecord::Base.connection
        connection.execute("INSERT INTO phoenix.job_owners (#{owner.keys.join(',')}) VALUES " \
                           "(#{owner.values.map { connection.quote(_1) }.join(',')})")
      end
      sequences.each do |sequence, state|
        a12rel_sql('SELECT setval(?, ?, ?)', sequence, state.fetch('last_value'), state.fetch('is_called'))
      end
      PhoenixSchema.reset!
    end
  end
end

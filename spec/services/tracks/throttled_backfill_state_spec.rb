# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tracks::ThrottledBackfillState do
  include ActiveSupport::Testing::TimeHelpers
  self.use_transactional_tests = false
  after(:context) { self.class.use_transactional_tests = true }

  let(:user_id) { 48_401 }
  let(:other_id) { 48_402 }
  let(:now) { Time.utc(2026, 10, 4, 12) }
  let(:connection) { ActiveRecord::Base.connection }

  before do
    phoenix_tables!
    phoenix_state!
    @owners = connection.select_all('SELECT * FROM phoenix.job_owners WHERE key IN ' \
                                   "('command:tracks.throttled_backfill', 'command:tracks.generate_range')").to_a
    connection.execute('INSERT INTO users (id, email, settings, created_at, updated_at) VALUES ' \
                       "(48401, 'k9@example.test', '{\"timezone\":\"Asia/Tokyo\"}', now(), now())")
    job_owner!('command:tracks.throttled_backfill', :sidekiq)
    job_owner!(Tracks::GenerationCommand::OWNER_KEY, :oban)
  end

  after do
    ids = JobOutbox.where(aggregate_id: [user_id, other_id],
                          command_type: %w[tracks.generate_range tracks.throttled_backfill]).pluck(:event_id)
    if ids.any?
      connection.execute(ActiveRecord::Base.sanitize_sql_array(
                           ['DELETE FROM phoenix.processed_commands WHERE event_id IN (?)', ids]
                         ))
    end
    JobOutbox.where(aggregate_id: [user_id, other_id],
                    command_type: %w[tracks.generate_range tracks.throttled_backfill])
             .delete_all
    connection.execute('DELETE FROM phoenix.track_backfill_walks WHERE user_id IN (48401, 48402)')
    connection.execute('DELETE FROM points WHERE id IN (48401, 48402) AND user_id = 48401')
    connection.execute('DELETE FROM users WHERE id = 48401')
    connection.execute('DELETE FROM phoenix.job_owners WHERE key IN ' \
                       "('command:tracks.throttled_backfill', 'command:tracks.generate_range')")
    @owners.each do |owner|
      columns = owner.keys.join(', ')
      values = owner.values.map { connection.quote(_1) }.join(', ')
      connection.execute("INSERT INTO phoenix.job_owners (#{columns}) VALUES (#{values})")
    end
    Sidekiq.redis { _1.del(redis_key(user_id), redis_key(other_id)) }
    PhoenixSchema.reset!
  end

  delegate :redis_key, to: :'Tracks::ThrottledBackfillJob'
  def user = User.find(user_id)
  def row = connection.select_one("SELECT * FROM phoenix.track_backfill_walks WHERE user_id = #{user_id}")

  def point!(id, timestamp)
    connection.execute('INSERT INTO points (id, user_id, timestamp, lonlat, created_at, updated_at) VALUES ' \
                       "(#{id}, #{user_id}, #{timestamp}, ST_GeomFromText('POINT(1 1)', 4326), now(), now())")
  end

  it 'Rails adopts legacy cursor and remaining backoff without duplicate scheduling' do
    travel_to now do
      Sidekiq.redis { _1.set(redis_key(user_id), 1, ex: 6.days.to_i) }
      expect(Tracks::ThrottledBackfillJob.schedule(user)).to be_falsey
      expect(row).to include('state' => 'backoff', 'cursor_timestamp' => nil)
      expect(row.fetch('expires_at')).to be_between(now + 6.days - 1, now + 6.days)
      expect(enqueued_jobs.select { _1[:job] == Tracks::ThrottledBackfillJob }).to be_empty
      expect(Sidekiq.redis { _1.exists(redis_key(user_id)) }).to eq(0)
      connection.execute('DELETE FROM phoenix.track_backfill_walks WHERE user_id = 48401')
      Sidekiq.redis { _1.set(redis_key(user_id), 1, ex: 10.hours.to_i) }
      expect(Tracks::ThrottledBackfillJob.schedule(user)).to be_falsey
      expect(row.fetch('cursor_timestamp')).to be_nil
      point!(48_401, 50)
      allow(Tracks::GenerationCommand).to receive(:forward).and_raise(IOError, 'generation failed')
      expect { Tracks::ThrottledBackfillJob.perform_now(user_id, 100) }.to raise_error(IOError, 'generation failed')
      selected = row
      expect(selected).to include('state' => 'walking', 'cursor_timestamp' => 100, 'selected_end_timestamp' => 50)
      expect(selected.fetch('expires_at')).to be_between(now + 10.hours - 1, now + 10.hours)
      expect(Sidekiq.redis { _1.exists(redis_key(user_id)) }).to eq(0)
      expect(JobOutbox.where(aggregate_id: user_id)).to be_empty
      allow(Tracks::GenerationCommand).to receive(:forward).and_call_original
      Tracks::ThrottledBackfillJob.perform_now(user_id, 100)
      expect(row.fetch('cursor_timestamp')).to eq(50 - 30.days.to_i)
      expect(row.fetch('expires_at')).to eq(now + 12.hours)
      expect(JobOutbox.find_by!(command_type: 'tracks.generate_range', aggregate_id: user_id).event_id)
        .to eq(selected.fetch('step_event_id'))

      Sidekiq.redis { _1.set(redis_key(other_id), 1, ex: 4.days.to_i) }
      ActiveRecord::Base.transaction do
        described_class.schedule(Struct.new(:id).new(other_id))
        Sidekiq.redis { _1.set(redis_key(other_id), 1, ex: 7.days.to_i) }
      end
      expect(Sidekiq.redis { _1.exists(redis_key(other_id)) }).to eq(1)
      described_class.schedule(Struct.new(:id).new(other_id))
      expect(Sidekiq.redis { _1.exists(redis_key(other_id)) }).to eq(0)
      expect(connection.select_value('SELECT expires_at FROM phoenix.track_backfill_walks WHERE user_id = 48402'))
        .to be_between(now + 7.days - 1, now + 7.days)
      Tracks::ThrottledBackfillJob.perform_now(other_id, nil)
      count = connection.select_value('SELECT count(*) FROM phoenix.track_backfill_walks WHERE user_id = 48402')
      expect(count).to eq(0)
      expect(row).to be_present

      connection.execute('DELETE FROM phoenix.track_backfill_walks WHERE user_id = 48401')
      Sidekiq.redis { _1.set(redis_key(user_id), 1, ex: 7.days.to_i) }
      allow(described_class).to receive(:upsert).and_raise(ActiveRecord::StatementInvalid, 'SQL failed')
      expect do
        Tracks::ThrottledBackfillJob.schedule(user)
      end.to raise_error(ActiveRecord::StatementInvalid, 'SQL failed')
      expect(Sidekiq.redis { _1.exists(redis_key(user_id)) }).to eq(1)
      allow(described_class).to receive(:upsert).and_call_original
      Sidekiq.redis { _1.del(redis_key(user_id)) }
      ActiveRecord::Base.transaction do
        connection.execute('DROP TABLE phoenix.track_backfill_walks')
        PhoenixSchema.reset!
        expect { Tracks::ThrottledBackfillJob.schedule(user) }
          .to have_enqueued_job(Tracks::ThrottledBackfillJob).with(user_id, nil)
        raise ActiveRecord::Rollback
      end
      PhoenixSchema.reset!
    end
  end

  it 'released native state is consumed by Rails with the same walk and cursor' do
    travel_to now do
      walk = SecureRandom.uuid
      step = SecureRandom.uuid
      first = 100 - 30.days.to_i
      sql = 'INSERT INTO phoenix.track_backfill_walks ' \
            '(user_id, walk_id, cursor_timestamp, step_event_id, selected_start_timestamp, selected_end_timestamp, ' \
            'state, expires_at, time_zone) VALUES (?, ?::uuid, 200, ?::uuid, ?, 100, \'walking\', ?, ?)'
      connection.execute(ActiveRecord::Base.sanitize_sql_array([sql, user_id, walk, step, first, now + 12.hours,
                                                                'Europe/Berlin']))
      point!(48_401, 150)
      job_owner!('command:tracks.throttled_backfill', :oban)
      JobOwnership.release!('command:tracks.throttled_backfill', by: 'test')
      allow(Tracks::GenerationCommand).to receive(:forward).and_raise(IOError, 'start failed')
      expect { Tracks::ThrottledBackfillJob.perform_now(user_id, 200, walk_id: walk, time_zone: 'Europe/Berlin') }
        .to raise_error(IOError, 'start failed')
      expect(row).to include('walk_id' => walk, 'cursor_timestamp' => 200, 'step_event_id' => step,
                             'selected_start_timestamp' => first, 'selected_end_timestamp' => 100)
      allow(Tracks::GenerationCommand).to receive(:forward).and_call_original
      Tracks::ThrottledBackfillJob.perform_now(user_id, 200, walk_id: walk, time_zone: 'Europe/Berlin')
      expect(JobOutbox.sole.event_id).to eq(step)
      expect(JobOutbox.sole.payload).to include('start_at' => Time.use_zone('Europe/Berlin') {
        Time.zone.at(first).iso8601(6)
      },
                                                'end_at' => Time.use_zone('Europe/Berlin') {
                                                  Time.zone.at(100).iso8601(6)
                                                },
                                                'time_zone' => 'Europe/Berlin', 'low_priority' => true)
      expect(row).to include('walk_id' => walk, 'cursor_timestamp' => first, 'step_event_id' => nil,
                             'selected_start_timestamp' => nil, 'selected_end_timestamp' => nil)
      expect(enqueued_jobs.count { _1[:job] == Tracks::ThrottledBackfillJob }).to eq(1)
      expect(enqueued_jobs.find { _1[:job] == Tracks::ThrottledBackfillJob }[:args])
        .to include(user_id, first, hash_including('walk_id' => walk, 'time_zone' => 'Europe/Berlin'))
      Tracks::ThrottledBackfillJob.perform_now(user_id, 200, walk_id: walk, time_zone: 'Europe/Berlin')
      expect(JobOutbox.count).to eq(1)
      expect(enqueued_jobs.count { _1[:job] == Tracks::ThrottledBackfillJob }).to eq(1)
      travel_to now + 12.hours
      expect(Tracks::ThrottledBackfillJob.schedule(user)).to be_truthy
      refute_walk = row.fetch('walk_id')
      expect(refute_walk).not_to eq(walk)
      Tracks::ThrottledBackfillJob.perform_now(user_id, first, walk_id: walk, time_zone: 'Europe/Berlin')
      expect(row.fetch('walk_id')).to eq(refute_walk)
      expect(row.fetch('cursor_timestamp')).to be_nil
    end
  end
end

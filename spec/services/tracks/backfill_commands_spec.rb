# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tracks::BackfillCommands do
  include ActiveSupport::Testing::TimeHelpers
  self.use_transactional_tests = false
  after(:context) { self.class.use_transactional_tests = true }

  let(:id) { 48_901 }
  let(:now) { Time.utc(2026, 10, 4, 12) }
  let(:connection) { ActiveRecord::Base.connection }
  let(:keys) { %w[command:tracks.backfill command:tracks.throttled_backfill command:tracks.generate_range] }

  before do
    phoenix_tables!
    phoenix_state!
    @reverse_sequence = connection.select_one('SELECT last_value,is_called FROM phoenix.rails_commands_id_seq')
    @events = []
    @owners = connection.select_all(ActiveRecord::Base.sanitize_sql_array(
                                      ['SELECT * FROM phoenix.job_owners WHERE key IN (?)', keys]
                                    )).to_a
    connection.execute('INSERT INTO users (id, email, settings, created_at, updated_at) ' \
                       "VALUES (48901, 'backfill-commands@example.test', '{}', now(), now())")
    keys.each { job_owner!(_1, :oban) }
  end

  after do
    types = %w[tracks.backfill tracks.throttled_backfill tracks.generate_range]
    ids = (@events + JobOutbox.where(aggregate_id: id, command_type: types).pluck(:event_id)).uniq
    if ids.any?
      connection.execute(ActiveRecord::Base.sanitize_sql_array(
                           ['DELETE FROM phoenix.processed_commands WHERE event_id IN (?)', ids]
                         ))
    end
    JobOutbox.where(aggregate_id: id, command_type: types).delete_all
    connection.execute("DELETE FROM phoenix.rails_commands WHERE (payload->>'user_id')::bigint = 48901")
    connection.execute(ActiveRecord::Base.sanitize_sql_array(
                         ["SELECT setval('phoenix.rails_commands_id_seq', ?, ?)",
                          @reverse_sequence.fetch('last_value'), @reverse_sequence.fetch('is_called')]
                       ))
    connection.execute('DELETE FROM phoenix.track_backfill_ranges WHERE user_id = 48901')
    connection.execute('DELETE FROM phoenix.track_backfill_walks WHERE user_id = 48901')
    connection.execute('DELETE FROM users WHERE id = 48901')
    connection.execute(ActiveRecord::Base.sanitize_sql_array(['DELETE FROM phoenix.job_owners WHERE key IN (?)', keys]))
    @owners.each do |owner|
      connection.execute("INSERT INTO phoenix.job_owners (#{owner.keys.join(', ')}) VALUES " \
                         "(#{owner.values.map { connection.quote(_1) }.join(', ')})")
    end
    Sidekiq.redis do
      _1.del("track_backfill_range:user:#{id}", "track_backfill:user:#{id}",
             Tracks::ThrottledBackfillJob.redis_key(id))
    end
    PhoenixSchema.reset!
  end

  def range = connection.select_one('SELECT * FROM phoenix.track_backfill_ranges WHERE user_id = 48901')
  def walk = connection.select_one('SELECT * FROM phoenix.track_backfill_walks WHERE user_id = 48901')

  def states
    cycle = SecureRandom.uuid
    @events << cycle
    Time.use_zone('Europe/Berlin') do
      Tracks::BackfillState.accumulate(id, [now.to_i - 100_000, now.to_i - 90_000], cycle, now)
      Tracks::ThrottledBackfillState.upsert(id, 200, 'walking', now + 12.hours, Time.zone.name, reclaim: false)
    end
    step = SecureRandom.uuid
    @events << step
    connection.execute(ActiveRecord::Base.sanitize_sql_array(
                         ['UPDATE phoenix.track_backfill_walks SET step_event_id = ?::uuid, ' \
                          'selected_start_timestamp = ?, selected_end_timestamp = 100 WHERE user_id = ?',
                          step, 100 - 30.days.to_i, id]
                       ))
    [range, walk]
  end

  def perform(job)
    @events << job.job_id
    job.perform_now
  end

  it 'aborted range enqueue retains its committed intent without consuming a newer cycle on replay' do
    travel_to now do
      initial, = states
      job_owner!('command:tracks.backfill', :sidekiq)
      job_owner!(Tracks::GenerationCommand::OWNER_KEY, :sidekiq)
      allow(Tracks::ParallelGeneratorJob).to receive(:perform_later).and_return(false)
      job = Tracks::BackfillGenerationJob.new(id, cycle_id: initial.fetch('cycle_id'), time_zone: 'Europe/Berlin')
      perform(job)
      expect(range).to be_nil
      pending = connection.select_all('SELECT id,payload FROM phoenix.rails_commands ' \
                                      "WHERE kind='tracks_generate_range' " \
                                      "AND (payload->>'user_id')::bigint = 48901").to_a
      expect(pending.size).to eq(1)
      payload = JSON.parse(pending.sole.fetch('payload'))
      expect(payload).to include('user_id' => id, 'time_zone' => 'Europe/Berlin', 'mode' => 'bulk',
                                 'untracked_only' => true)
      fresh = SecureRandom.uuid
      @events << fresh
      Tracks::BackfillState.accumulate(id, [now.to_i - 200_000], fresh, now)
      perform(job)
      expect(range.fetch('cycle_id')).to eq(fresh)
      expect { RailsCommands::Poller.deliver(pending.sole.fetch('id')) }.to raise_error(/enqueue aborted/)
      allow(Tracks::ParallelGeneratorJob).to receive(:perform_later).and_call_original
      2.times { RailsCommands::Poller.deliver(pending.sole.fetch('id')) }
      expect(enqueued_jobs.count { _1[:job] == Tracks::ParallelGeneratorJob }).to eq(1)
      expect(range.fetch('cycle_id')).to eq(fresh)
    end
  end

  it 'old queued jobs forward under native authority before consuming shared state' do
    travel_to now do
      initial_range, initial_walk = states
      perform(Tracks::BackfillGenerationJob.new(id))
      perform(Tracks::ThrottledBackfillJob.new(id, 200))
      expect(range).to eq(initial_range)
      expect(walk).to eq(initial_walk)
      expect(JobOutbox.where(aggregate_id: id).order(:command_type).pluck(:command_type))
        .to eq(%w[tracks.backfill tracks.throttled_backfill])
      range_command = JobOutbox.find_by!(command_type: 'tracks.backfill', aggregate_id: id)
      expect(range_command.event_id).to eq(initial_range.fetch('cycle_id'))
      expect(range_command.payload).to eq(initial_range.slice('user_id', 'cycle_id', 'time_zone'))
      walk_command = JobOutbox.find_by!(command_type: 'tracks.throttled_backfill', aggregate_id: id)
      expect(walk_command.payload).to eq(initial_walk.slice('user_id', 'walk_id', 'cursor_timestamp', 'time_zone'))
      expect(walk_command.event_id).to eq(@events.last)
      expect(enqueued_jobs.select { _1[:job] == Tracks::ParallelGeneratorJob }).to be_empty
      perform(Tracks::BackfillGenerationJob.new(id, cycle_id: initial_range.fetch('cycle_id'),
                                                  time_zone: 'Europe/Berlin'))
      expect(JobOutbox.where(command_type: 'tracks.backfill').count).to eq(1)
      expect(range).to eq(initial_range)

      connection.execute('DELETE FROM phoenix.track_backfill_ranges WHERE user_id = 48901')
      JobOutbox.where(command_type: 'tracks.backfill', aggregate_id: id).delete_all
      Sidekiq.redis do |redis|
        redis.zadd("track_backfill_range:user:#{id}", now.to_i - 300_000, (now.to_i - 300_000).to_s)
        redis.set("track_backfill:user:#{id}", 1, ex: 300)
      end
      perform(Tracks::BackfillGenerationJob.new(id, time_zone: 'Europe/Berlin'))
      @events << range.fetch('cycle_id')
      expect(range.fetch('earliest_timestamp')).to eq(now.to_i - 300_000)
      expect(range.fetch('time_zone')).to eq('Europe/Berlin')
      command = JobOutbox.find_by!(command_type: 'tracks.backfill')
      expect(command.payload.fetch('cycle_id')).to eq(range.fetch('cycle_id'))
      expect(Sidekiq.redis { _1.exists("track_backfill_range:user:#{id}") }).to eq(0)
    end
  end

  it 'pending range and walk commands rehome preserving due time zone and tokens' do
    travel_to now do
      initial_range, initial_walk = states
      at = now + 5.minutes
      { 'tracks.backfill' => initial_range.slice('user_id', 'cycle_id', 'time_zone'),
        'tracks.throttled_backfill' => initial_walk.slice('user_id', 'walk_id', 'cursor_timestamp', 'time_zone') }
        .each do |type, payload|
          event = type == 'tracks.backfill' ? initial_range.fetch('cycle_id') : SecureRandom.uuid
          @events << event
          JobCommands.forward(type, payload, event_id: event, aggregate_id: id, producer: 'spec', scheduled_at: at)
          expect(JobCommands.rehome!(type, by: 'test')).to include(moved: 1, left: 0)
        end
      expect(JobOutbox.where(aggregate_id: id)).to be_empty
      jobs = enqueued_jobs.select { _1[:job].in?([Tracks::BackfillGenerationJob, Tracks::ThrottledBackfillJob]) }
      expect(jobs.size).to eq(2)
      expect(jobs.map { _1[:at] }).to eq([at.to_f, at.to_f])
      expect(jobs.first[:args]).to include(id, hash_including('cycle_id' => initial_range.fetch('cycle_id'),
                                                              'time_zone' => 'Europe/Berlin'))
      expect(jobs.last[:args]).to include(id, 200, hash_including('walk_id' => initial_walk.fetch('walk_id'),
                                                                  'time_zone' => 'Europe/Berlin'))
      reverse = initial_walk.slice('user_id', 'walk_id', 'cursor_timestamp', 'time_zone')
                            .merge('event_id' => SecureRandom.uuid, 'scheduled_at' => at.iso8601(6))
      RailsCommands::Registry.handler('tracks_throttled_backfill').call(reverse)
      expect(enqueued_jobs.last[:args]).to include(id, 200, hash_including('walk_id' => initial_walk.fetch('walk_id')))
      expect(enqueued_jobs.last[:at]).to eq(at.to_f)
      expect(walk).to eq(initial_walk)
      perform(Tracks::BackfillGenerationJob.new(id, cycle_id: initial_range.fetch('cycle_id'),
time_zone: 'Europe/Berlin'))
      expect(range).to be_nil
      expect(JobOutbox.sole.command_type).to eq('tracks.generate_range')
      expect(JobOutbox.sole.payload).to include('time_zone' => 'Europe/Berlin', 'low_priority' => false,
                                                'untracked_only' => true, 'mode' => 'bulk')
      fresh = SecureRandom.uuid
      @events << fresh
      Time.use_zone('Europe/Berlin') do
        Tracks::BackfillState.accumulate(id, [now.to_i - 200_000], fresh, now)
      end
      perform(Tracks::BackfillGenerationJob.new(id, cycle_id: initial_range.fetch('cycle_id'),
time_zone: 'Europe/Berlin'))
      expect(range.fetch('cycle_id')).to eq(fresh)
      expect(JobOutbox.count).to eq(1)
      allow(Tracks::GenerationCommand).to receive(:forward).and_raise(IOError, 'child publication failed')
      perform(Tracks::BackfillGenerationJob.new(id, cycle_id: fresh, time_zone: 'Europe/Berlin'))
      expect(range.fetch('cycle_id')).to eq(fresh)
      expect(range.fetch('earliest_timestamp')).to eq(now.to_i - 200_000)
      expect(range.fetch('due_at')).to eq(now + 1.minute)
      allow(Tracks::GenerationCommand).to receive(:forward).and_call_original
      job_owner!(Tracks::GenerationCommand::OWNER_KEY, :sidekiq)
      perform(Tracks::BackfillGenerationJob.new(id, cycle_id: fresh, time_zone: 'Europe/Berlin'))
      expect(range).to be_nil
      child = enqueued_jobs.reverse.find { _1[:job] == Tracks::ParallelGeneratorJob }
      expect(child.fetch('timezone')).to eq('Europe/Berlin')

      connection.execute('DELETE FROM phoenix.track_backfill_walks WHERE user_id = 48901')
      Tracks::ThrottledBackfillJob.schedule(User.find(id))
      legacy = Tracks::ThrottledBackfillJob.new(id, nil)
      perform(legacy)
      expect(walk.fetch('state')).to eq('backoff')
      travel_to now + 7.days
      Tracks::ThrottledBackfillJob.schedule(User.find(id))
      next_walk = walk
      perform(legacy)
      expect(walk).to eq(next_walk)
    end
  end
end

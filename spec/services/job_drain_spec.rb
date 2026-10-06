# frozen_string_literal: true

require 'rails_helper'
require 'sidekiq/api'

RSpec.describe 'JobDrain' do
  it 'drain status blocks queued scheduled retry dead busy and unknown work without exposing payloads' do
    phoenix_tables!
    token = SecureRandom.hex(8)
    queue = "a12d3-drain-#{token}"
    other_queue = "a12d3-drain-other-#{token}"
    process = "a12d3-drain-process-#{token}"
    secret = 'synthetic-private-payload@example.test'
    payload = {
      'class' => 'Sidekiq::ActiveJob::Wrapper', 'wrapped' => 'BulkVisitsSuggestingJob',
      'queue' => queue, 'jid' => token, 'args' => [{ 'job_class' => 'BulkVisitsSuggestingJob',
                                                 'arguments' => [secret, { 'lat' => 52.5, 'lon' => 13.4 }] }]
    }
    message = JSON.generate(payload)
    unknown = JSON.generate(payload.merge('class' => 'SyntheticForeignWorker', 'wrapped' => nil))
    framework = JSON.generate(payload.merge('wrapped' => 'ActiveStorage::PurgeJob'))
    baseline = JobDrain.status

    begin
      Sidekiq.redis do |redis|
        redis.sadd('queues', queue, other_queue)
        redis.lpush("queue:#{queue}", message)
        redis.lpush("queue:#{other_queue}", framework, unknown)
        redis.zadd('schedule', 1.hour.from_now.to_f, message)
        redis.zadd('retry', 1.hour.from_now.to_f, message)
        redis.zadd('dead', Time.current.to_f, message)
        redis.sadd('processes', process)
        redis.hset(process, 'info', JSON.generate('identity' => process), 'busy', '1',
                   'beat', Time.current.to_f.to_s)
        redis.hset("#{process}:work", 'synthetic-thread',
                   JSON.generate('queue' => queue, 'run_at' => Time.current.to_i, 'payload' => message))
      end
      status = JobDrain.status
      expect(status[:status]).to eq('BLOCKED')
      expect(status[:observation]).to be(true)
      { queued: 3, scheduled: 1, retry: 1, dead: 1, busy: 1, unknown: 1 }.each do |key, added|
        expect(status[:counts][key]).to eq(baseline[:counts][key] + added), key.to_s
      end
      expect(status[:classes]).to include('BulkVisitsSuggestingJob' => 5, 'ActiveStorage::PurgeJob' => 1,
                                          'unknown' => 1)
      rendered = JSON.generate(status)
      expect(rendered).not_to include(secret, '52.5', '13.4', process, queue, 'args', 'last_error')
      expect(Sidekiq::ScheduledSet.new.size).to eq(baseline[:counts][:scheduled] + 1)
      expect(Sidekiq::DeadSet.new.size).to eq(baseline[:counts][:dead] + 1)

      allow(Sidekiq::Queue).to receive(:all).and_raise(RedisClient::CannotConnectError, secret)
      expect(JobDrain.status).to include(status: 'BLOCKED', reasons: ['redis_unreadable'])
      expect(JSON.generate(JobDrain.status)).not_to include(secret)
      allow(Sidekiq::Queue).to receive(:all).and_call_original
      allow(JobHealth).to receive(:gauges).and_return(tables: :unknown)
      expect(JobDrain.status[:reasons]).to include('database_unreadable')
    ensure
      Sidekiq.redis do |redis|
        redis.lrem("queue:#{queue}", 0, message)
        redis.lrem("queue:#{other_queue}", 0, framework)
        redis.lrem("queue:#{other_queue}", 0, unknown)
        %w[schedule retry dead].each { |set| redis.zrem(set, message) }
        redis.srem('queues', queue, other_queue)
        redis.srem('processes', process)
        redis.del(process, "#{process}:work")
      end
    end
  end
  it 'Cloud source drain blocks reserved fetches and every retained queue retry dead busy or unknown payload' do
    allow(JobHealth).to receive(:gauges).and_return(empty_gauges)
    expect(JobDrain.status[:status]).to eq('OBSERVED_EMPTY')
    queue = Sidekiq::Queue['trips']
    message = drain_payload
    fetcher = Sidekiq::LimitFetch::Global::Selector.uuid
    monitor = Sidekiq::LimitFetch::Global::Monitor
    begin
      %w[queue:trips schedule retry dead].each do |key|
        Sidekiq.redis do |redis|
          key.start_with?('queue:') ? redis.lpush(key, message) : redis.zadd(key, 1.hour.from_now.to_f, message)
        end
        expect(JobDrain.status[:status]).to eq('BLOCKED'), key
        expect(Sidekiq.redis { |redis| redis.call('TYPE', key) }).not_to eq('none')
        Sidekiq.redis { |redis| redis.del(key) }
      end
      ['SyntheticForeignWorker', 'Retired::CloudWrapper', 'BulkVisitsSuggestingJob',
       'ActionMailer::MailDeliveryJob'].each do |name|
        Sidekiq.redis { |redis| redis.lpush('queue:trips', drain_payload(name)) }
        expect(JobDrain.status[:reasons]).to include('queued_work')
        refute_payload(JobDrain.status)
        Sidekiq.redis { |redis| redis.del('queue:trips') }
      end
      Sidekiq.redis do |redis|
        redis.sadd(monitor::PROCESS_SET, fetcher)
        redis.set(monitor::HEARTBEAT_PREFIX + fetcher, '1')
      end
      Sidekiq.redis { |redis| redis.lpush('queue:synthetic-orphan', message) }
      expect(JobDrain.status[:reasons]).to include('queued_work')
      Sidekiq.redis { |redis| redis.del('queue:synthetic-orphan') }
      expect(queue.acquire).to be(true)
      expect(JobDrain.status[:reasons]).to include('fetchers_present', 'fetch_probes_present')
      expect(JobDrain.status[:counts][:queued]).to eq(0)
      expect(JobDrain.status(phase: :pre_quiet)[:status]).to eq('OBSERVED_EMPTY')
      fetched = Sidekiq::LimitFetch::UnitOfWork.new('queue:trips', message)
      expect(JobDrain.status(phase: :pre_quiet)[:reasons]).to include('fetched_work', 'fetch_state_inconsistent')
      fetched.acknowledge
      expect(JobDrain.status[:reasons]).to include('fetchers_present')
      Sidekiq.redis { |redis| redis.srem(monitor::PROCESS_SET, fetcher) }
      expect(JobDrain.status[:status]).to eq('OBSERVED_EMPTY')
      Sidekiq.redis do |redis|
        redis.sadd('processes', 'synthetic-drain-worker')
        redis.hset('synthetic-drain-worker', 'info', JSON.generate('identity' => 'synthetic-drain-worker'),
                   'busy', '1', 'beat', Time.current.to_f.to_s)
      end
      expect(JobDrain.status[:reasons]).to include('busy_unreadable', 'busy_work')
    ensure
      queue.release
      Sidekiq.redis do |redis|
        redis.srem(monitor::PROCESS_SET, fetcher)
        redis.del(monitor::HEARTBEAT_PREFIX + fetcher, 'queue:trips', 'queue:synthetic-orphan',
                  'synthetic-drain-worker')
        redis.srem('processes', 'synthetic-drain-worker')
      end
    end
  end

  it 'Cloud quiet drain accepts only explicitly stopping Sidekiq process records' do
    allow(JobHealth).to receive(:gauges).and_return(empty_gauges)
    process = "synthetic-quiet-drain-#{SecureRandom.hex(8)}"
    fetcher = "synthetic-quiet-fetcher-#{SecureRandom.hex(8)}"
    monitor = Sidekiq::LimitFetch::Global::Monitor

    begin
      Sidekiq.redis do |redis|
        redis.sadd('processes', process)
        redis.hset(process, 'info', JSON.generate('identity' => process), 'busy', '0',
                   'beat', Time.current.to_f.to_s)
        redis.sadd(monitor::PROCESS_SET, fetcher)
        redis.set(monitor::HEARTBEAT_PREFIX + fetcher, '1')
      end

      aggregate_failures do
        ['false', 'true', nil, 'unknown'].each do |quiet|
          Sidekiq.redis do |redis|
            quiet.nil? ? redis.hdel(process, 'quiet') : redis.hset(process, 'quiet', quiet)
          end
          expect(Sidekiq::ProcessSet.new(false).to_a.sole['quiet']).to eq(quiet)
          expect(JobDrain.status(phase: :pre_quiet)).to include(status: 'OBSERVED_EMPTY', certainty: 'OBSERVED')
          status = JobDrain.status(phase: :quiet)
          expect(status[:fetch]).to eq(busy: 0, probed: 0, processes: 1)
          expect(status[:counts].values).to all(eq(0))
          expect(status[:bridge][:shutdown]).to eq('OBSERVED_EMPTY')
          expected_status = quiet == 'true' ? 'OBSERVED_EMPTY' : 'BLOCKED'
          expected_reasons = quiet == 'true' ? [] : ['processes_not_quiet']
          expect(status).to include(status: expected_status, certainty: 'OBSERVED', reasons: expected_reasons),
                            "quiet=#{quiet.inspect}"
        end
      end
    ensure
      Sidekiq.redis do |redis|
        redis.srem('processes', process)
        redis.srem(monitor::PROCESS_SET, fetcher)
        redis.del(process, monitor::HEARTBEAT_PREFIX + fetcher)
      end
    end
  end

  it 'Cloud source drain read failures and changing observations remain UNKNOWN and block shutdown' do
    allow(JobHealth).to receive(:gauges).and_return(empty_gauges)
    allow(Sidekiq::Queue).to receive(:all).and_raise(RedisClient::CannotConnectError, 'synthetic-private-error')
    expect(JobDrain.status).to include(status: 'BLOCKED', certainty: 'UNKNOWN', reasons: ['redis_unreadable'])
    refute_payload(JobDrain.status)
    allow(Sidekiq::Queue).to receive(:all).and_call_original
    allow(JobHealth).to receive(:gauges).and_call_original
    phoenix_tables!
    allow(JobHealth.connection).to receive(:select_one).and_raise(ActiveRecord::StatementInvalid,
                                                                  'synthetic-private-error')
    expect(JobDrain.status).to include(status: 'BLOCKED', certainty: 'UNKNOWN')
    expect(JobDrain.status[:reasons]).to include('database_unreadable')
    allow(JobHealth.connection).to receive(:select_one).and_call_original
    allow(JobHealth).to receive(:gauges).and_return(empty_gauges)
    stale = empty_gauges
    stale[:drain][:counts]['stale_nodes'] = 1
    allow(JobHealth).to receive(:gauges).and_return(stale)
    expect(JobDrain.status).to include(status: 'BLOCKED', certainty: 'UNKNOWN')
    expect(JobDrain.status[:bridge][:binary_reasons]).to include('heartbeat_invalid')
    allow(JobHealth).to receive(:gauges).and_return(empty_gauges)
    Sidekiq.redis { |redis| redis.sadd('processes', 'synthetic-missing-info') }
    begin
      expect(JobDrain.status).to include(status: 'BLOCKED', certainty: 'UNKNOWN')
      expect(JobDrain.status[:reasons]).to include('process_registration_unreadable')
    ensure
      Sidekiq.redis { |redis| redis.srem('processes', 'synthetic-missing-info') }
    end
    Sidekiq.redis { |redis| redis.hset('synthetic-orphan:work', 'thread', 'synthetic-private-error') }
    begin
      expect(JobDrain.status).to include(status: 'BLOCKED', certainty: 'UNKNOWN')
      expect(JobDrain.status[:reasons]).to include('busy_unreadable')
      refute_payload(JobDrain.status)
    ensure
      Sidekiq.redis { |redis| redis.del('synthetic-orphan:work') }
    end
    process = 'synthetic-stale-drain-worker'
    begin
      Sidekiq.redis do |redis|
        redis.sadd('processes', process)
        redis.hset(process, 'info', JSON.generate('identity' => process), 'busy', '0',
                   'beat', 2.minutes.ago.to_f.to_s)
      end
      expect(JobDrain.status).to include(status: 'BLOCKED', certainty: 'UNKNOWN')
      expect(JobDrain.status[:reasons]).to include('process_heartbeat_invalid')
      Sidekiq.redis do |redis|
        redis.srem('processes', process)
        redis.del(process)
      end
      allow(JobHealth).to receive(:gauges) do
        Sidekiq.redis { |redis| redis.lpush('queue:trips', drain_payload) }
        empty_gauges
      end
      expect(JobDrain.status).to include(status: 'BLOCKED', certainty: 'UNKNOWN')
      expect(JobDrain.status[:reasons]).to include('changed_during_read')
      expect(Sidekiq.redis { |redis| redis.llen('queue:trips') }).to be_positive
      refute_payload(JobDrain.status)
    ensure
      Sidekiq.redis do |redis|
        redis.srem('processes', process)
        redis.del(process, 'queue:trips')
      end
    end
  end

  def drain_payload(name = 'BulkVisitsSuggestingJob')
    JSON.generate('class' => 'Sidekiq::ActiveJob::Wrapper', 'wrapped' => name, 'queue' => 'trips',
                  'jid' => 'synthetic-drain', 'args' => ['synthetic-private-error'])
  end

  def empty_gauges
    keys = %w[pending_outbox quarantined reverse_pending reverse_dead release_pending incomplete_oban
              unfinished_generations missing_owners mixed_owners unknown_owners unpinned_rollback_owners
              oban_owners fresh_nodes stale_nodes]
    { tables: true, drain: { tables: true, counts: keys.index_with { 0 }, legacy_schedulers: [], producer_kinds: [] } }
  end

  def refute_payload(status)
    expect(JSON.generate(status)).not_to include('synthetic-private-error', 'synthetic-drain-worker', 'args')
  end
end

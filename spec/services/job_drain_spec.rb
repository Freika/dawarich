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
end

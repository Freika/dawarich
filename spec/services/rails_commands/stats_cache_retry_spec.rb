# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'R3 reverse nightly stats cleanup' do
  let(:user) { create(:user) }
  let(:redis) { Redis.new(url: ENV.fetch('REDIS_URL')) }
  let(:cache) do
    ActiveSupport::Cache::RedisCacheStore.new(redis: redis, pool: false, namespace: 'stats-retry')
  end

  def sql(statement, *binds)
    ActiveRecord::Base.connection.execute(ActiveRecord::Base.sanitize_sql_array([statement, *binds]))
  end

  def enqueue_cleanup(scope)
    sql('INSERT INTO phoenix.rails_commands(kind,payload) VALUES(?,?::jsonb) RETURNING id',
        'stats.caches_invalidated', { user_id: user.id, year: nil, scope: scope }.to_json).first.fetch('id')
  end

  def pending
    sql('SELECT id,attempts,leased_until FROM phoenix.rails_commands ORDER BY id').to_a
  end

  it 'R3 retains a failed UNLINK command despite recovered later operations, then retries absent keys idempotently' do
    phoenix_tables!
    allow(Rails).to receive(:cache).and_return(cache)

    %w[all toponyms].each do |scope|
      suffixes = %w[countries_visited cities_visited]
      suffixes += %w[points_geocoded_stats total_distance] if scope == 'all'
      keys = suffixes.map { |suffix| "dawarich/user_#{user.id}_#{suffix}" }
      digest = "insights/yearly_digest/#{user.id}/2026/synthetic"
      keys.each do |failed_key|
        (keys + [digest]).each { |key| expect(cache.write(key, ['synthetic-before'])).to be(true) }
        failures = 0
        allow(redis).to receive(:unlink).and_wrap_original do |original, *names|
          if names == ["stats-retry:#{failed_key}"] && failures.zero?
            failures += 1
            raise Redis::TimeoutError, 'synthetic first-delete timeout'
          end
          original.call(*names)
        end
        id = enqueue_cleanup(scope)

        expect(RailsCommands::Poller.drain_once).to eq(1)
        expect(failures).to eq(1)
        expect(cache.read(failed_key)).to eq(['synthetic-before'])
        expect(redis.unlink('stats-retry:synthetic-recovered-operation')).to eq(0)
        expect(pending).to contain_exactly(include('id' => id, 'attempts' => 1, 'leased_until' => nil))
        expect(sql('SELECT count(*) FROM phoenix.rails_commands_dead').first.fetch('count')).to eq(0)

        sql('UPDATE phoenix.rails_commands SET available_at = now() WHERE id = ?', id)
        expect(RailsCommands::Poller.drain_once).to eq(1)
        expect(pending).to be_empty
        (keys + [digest]).each { |key| expect(cache.read(key)).to be_nil }

        enqueue_cleanup(scope)
        expect(RailsCommands::Poller.drain_once).to eq(1)
        expect(pending).to be_empty
        expect(failures).to eq(1)
      end
    end

    pool = ConnectionPool.new(size: 1, timeout: 0.1) { redis }
    pooled_cache = ActiveSupport::Cache::RedisCacheStore.new(redis: pool, namespace: 'stats-retry')
    allow(Rails).to receive(:cache).and_return(pooled_cache)
    key = "dawarich/user_#{user.id}_countries_visited"
    expect(pooled_cache.write(key, ['synthetic-before'])).to be(true)
    checkouts = 0
    allow(pool).to receive(:then).and_wrap_original do |original, *args, **options, &block|
      checkouts += 1
      raise ConnectionPool::TimeoutError, 'synthetic checkout timeout' if checkouts == 1

      original.call(*args, **options, &block)
    end
    id = enqueue_cleanup('all')
    expect(RailsCommands::Poller.drain_once).to eq(1)
    expect(pending).to contain_exactly(include('id' => id, 'attempts' => 1, 'leased_until' => nil))
    expect(pooled_cache.read(key)).to eq(['synthetic-before'])
    sql('UPDATE phoenix.rails_commands SET available_at = now() WHERE id = ?', id)
    expect(RailsCommands::Poller.drain_once).to eq(1)
    expect(pending).to be_empty
    expect(pooled_cache.read(key)).to be_nil

    expect(cache.write(key, ['synthetic-before'])).to be(true)
    allow(redis).to receive(:unlink).with("stats-retry:#{key}").and_raise(Redis::TimeoutError)
    expect(cache.delete(key)).to be(false)
    expect(cache.read(key)).to eq(['synthetic-before'])
  ensure
    redis.scan_each(match: 'stats-retry:*') { |key| redis.del(key) }
    redis.close
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Stats::GeocodedDays do
  include ActiveSupport::Testing::TimeHelpers
  let(:user) { create(:user, settings: { 'timezone' => 'Asia/Tokyo' }) }
  let(:timestamp) { Time.utc(2014, 12, 31, 23, 30).to_i }

  before { clear_geocoded_days }
  after { clear_geocoded_days }

  shared_examples 'a geocoded-days queue' do
    it 'coalesces points without postponing a continuously changing day forever' do
      described_class.mark(user.id, timestamp)
      travel 59.minutes do
        described_class.mark(user.id, timestamp + 1)
        expect(described_class.due(limit: 10)).to be_empty
      end
      travel 61.minutes do
        expect(described_class.due(limit: 10).size).to eq(1)
      end
    end

    it 'preserves a new event when an older calculation acknowledges completion' do
      described_class.mark(user.id, timestamp)
      travel 61.minutes do
        snapshot = described_class.due(limit: 10)
        described_class.mark(user.id, timestamp)
        described_class.acknowledge(snapshot)
        expect(described_class.due(limit: 10)).to be_empty
      end
      travel 122.minutes do
        expect(described_class.due(limit: 10).size).to eq(1)
        described_class.acknowledge(described_class.due(limit: 10))
        expect(described_class.due(limit: 10)).to be_empty
      end
    end

    it 'includes both local months for a UTC day crossing the year boundary' do
      described_class.mark(user.id, timestamp)
      travel 61.minutes do
        member = described_class.due(limit: 10).keys.first
        expect(described_class.local_months(member, user)).to eq([[2014, 12], [2015, 1]])
      end
    end

    it 'does not acknowledge boundary days with only one local month calculated' do
      described_class.mark(user.id, timestamp)
      expect(described_class.snapshot_month(user, 2015, 1)).to be_empty
    end

    it 'can acknowledge the interior days covered by a full month calculation' do
      described_class.mark(user.id, Time.utc(2015, 1, 12).to_i)
      snapshot = described_class.snapshot_month(user, 2015, 1)
      expect(snapshot.size).to eq(1)
      described_class.acknowledge(snapshot)
      travel 61.minutes do
        expect(described_class.due(limit: 10)).to be_empty
      end
    end
  end

  context 'on Redis, where Phoenix never migrated' do
    it_behaves_like 'a geocoded-days queue'

    it 'keeps pending snapshots optional when Redis is unavailable' do
      account = user
      allow(Sidekiq).to receive(:redis).and_raise(RedisClient::CannotConnectError, 'unavailable')
      expect(described_class.snapshot_month(account, 2015, 1)).to eq({})
    ensure
      allow(Sidekiq).to receive(:redis).and_call_original
    end
  end

  context 'on phoenix.stats_geocoded_days' do
    before { phoenix_tables! }

    it_behaves_like 'a geocoded-days queue'

    it 'keeps the day in a row with a fresh version and an unchanged due second, never in Redis' do
      travel_to(Time.utc(2026, 10, 3, 12)) do
        described_class.mark(user.id, timestamp)
        first = queue_rows
        described_class.mark(user.id, timestamp)

        expect(first).to eq([["#{user.id}:2014-12-31", first[0][1], Time.utc(2026, 10, 3, 13).to_i]])
        expect(queue_rows[0][1]).not_to eq(first[0][1])
        expect(queue_rows[0][2]).to eq(first[0][2])
      end
      expect(Sidekiq.redis { |redis| redis.call('ZCARD', described_class::PENDING_KEY) }).to eq(0)
    end

    it 'moves pending Redis days into rows due at once, gives a held row a fresh version, and clears Redis' do
      redis_member = "#{user.id}:2014-12-31"
      held_member = "#{user.id}:2015-01-12"
      described_class.mark(user.id, Time.utc(2015, 1, 12).to_i)
      _held, held_version, held_due = queue_rows.first
      redis_pending(redis_member, 'redis-version')
      redis_pending(held_member, 'stale-redis-version')

      travel_to(Time.utc(2026, 10, 3, 12)) { described_class.drain_redis }

      expect(queue_rows).to contain_exactly([redis_member, 'redis-version', Time.utc(2026, 10, 3, 12).to_i],
                                            [held_member, kind_of(String), held_due])
      expect(queue_rows.last[1]).not_to eq(held_version)
      expect(queue_rows.last[1]).not_to eq('stale-redis-version')
      expect(redis_size).to eq(0)
      expect(Sidekiq.redis { |redis| redis.call('EXISTS', "#{described_class::VERSION_KEY_PREFIX}:#{redis_member}") })
        .to eq(0)
    end

    it 'keeps a day a Redis mark changed while a calculation held its snapshot' do
      member = "#{user.id}:2015-01-12"
      described_class.mark(user.id, Time.utc(2015, 1, 12).to_i)
      snapshot = described_class.snapshot_month(user, 2015, 1)
      redis_pending(member, 'old-code-version')

      described_class.drain_redis
      described_class.acknowledge(snapshot)

      expect(queue_rows.map(&:first)).to eq([member])
    end

    it 'never lets a second drain carrying an already drained version re-arm a calculation snapshot' do
      member = "#{user.id}:2015-01-12"
      redis_pending(member, 'drained-version')
      described_class.drain_redis
      snapshot = described_class.snapshot_month(user, 2015, 1)
      described_class.mark(user.id, Time.utc(2015, 1, 12).to_i)
      redis_pending(member, 'drained-version')

      described_class.drain_redis
      described_class.acknowledge(snapshot)

      expect(queue_rows.map(&:first)).to eq([member])
    end

    it 'leaves a day in Redis when its version changes during the drain, and drains it next time' do
      member = "#{user.id}:2015-01-12"
      redis_pending(member, 'first-version')
      allow(described_class).to receive(:release).and_wrap_original do |original, redis, *args|
        redis.call('SET', "#{described_class::VERSION_KEY_PREFIX}:#{member}", 'second-version')
        original.call(redis, *args)
      end

      described_class.drain_redis
      expect(queue_rows).to match([[member, 'first-version', kind_of(Integer)]])
      expect(redis_size).to eq(1)

      allow(described_class).to receive(:release).and_call_original
      described_class.drain_redis
      expect(redis_size).to eq(0)
      expect(queue_rows.first[1]).not_to eq('first-version')
    end

    it 'drains a pending Redis day whose version key is missing with a fresh version' do
      member = "#{user.id}:2015-01-12"
      Sidekiq.redis { |redis| redis.call('ZADD', described_class::PENDING_KEY, 1, member) }

      described_class.drain_redis

      expect(queue_rows).to match([[member, kind_of(String), kind_of(Integer)]])
      expect(redis_size).to eq(0)
    end

    it 'keeps every Redis day when the insert fails' do
      member = "#{user.id}:2015-01-12"
      redis_pending(member, 'kept-version')
      allow(described_class).to receive(:query).and_wrap_original do |original, sql, *binds|
        raise ActiveRecord::StatementInvalid, 'insert failed' if sql == described_class::DRAIN

        original.call(sql, *binds)
      end

      expect { described_class.drain_redis }.to raise_error(ActiveRecord::StatementInvalid)
      expect(redis_size).to eq(1)
      expect(Sidekiq.redis { |redis| redis.call('GET', "#{described_class::VERSION_KEY_PREFIX}:#{member}") })
        .to eq('kept-version')
    end

    it 'drains Redis in batches' do
      stub_const("#{described_class}::DRAIN_BATCH", 2)
      (1..5).each { |day| redis_pending("#{user.id}:2015-01-0#{day}", "version-#{day}") }

      described_class.drain_redis

      expect(queue_rows.map(&:second)).to eq((1..5).map { |day| "version-#{day}" })
      expect(redis_size).to eq(0)
    end

    it 'skips the drain with a warning while Redis is unavailable' do
      allow(Sidekiq).to receive(:redis).and_raise(RedisClient::CannotConnectError, 'unavailable')
      allow(Rails.logger).to receive(:warn)

      expect { described_class.drain_redis }.not_to raise_error
      expect(Rails.logger).to have_received(:warn).with(/geocoded-days drain skipped/)
    ensure
      allow(Sidekiq).to receive(:redis).and_call_original
    end

    it 'issues the statements Dawarich.Stats.GeocodedDays issues' do
      source = Rails.root.join('app-phoenix/lib/dawarich/stats/geocoded_days.ex').read.squish
      %w[MARK DUE SNAPSHOT ACKNOWLEDGE POSTPONE].each do |name|
        expect(source).to include(described_class.const_get(name).squish)
      end
    end
  end

  def redis_pending(member, version)
    Sidekiq.redis do |redis|
      redis.call('SET', "#{described_class::VERSION_KEY_PREFIX}:#{member}", version)
      redis.call('ZADD', described_class::PENDING_KEY, 1, member)
    end
  end

  def redis_size
    Sidekiq.redis { |redis| redis.call('ZCARD', described_class::PENDING_KEY) }
  end

  def queue_rows
    ActiveRecord::Base.connection.select_rows(
      'SELECT member, version, due_at FROM phoenix.stats_geocoded_days ORDER BY member'
    )
  end
end

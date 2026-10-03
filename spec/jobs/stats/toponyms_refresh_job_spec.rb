# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Stats::ToponymsRefreshJob do
  it 'runs the refresh service on the stats queue' do
    service = instance_double(Stats::ToponymsRefresh, call: true)
    allow(Stats::ToponymsRefresh).to receive(:new).and_return(service)

    expect(described_class.queue_name).to eq('stats')
    described_class.perform_now
    expect(service).to have_received(:call).once
  end

  it 'Oban-owned: does not refresh' do
    job_owner!(described_class::OWNER_KEY, :oban)
    allow(Stats::ToponymsRefresh).to receive(:new)

    described_class.perform_now

    expect(Stats::ToponymsRefresh).not_to have_received(:new)
  end

  context 'with the Phoenix tables and days still pending in Redis' do
    let(:user) { create(:user, settings: { 'timezone' => 'Etc/UTC', 'min_minutes_spent_in_city' => 0 }) }
    let(:member) { "#{user.id}:2014-06-15" }
    let!(:stat) { create(:stat, user: user, year: 2014, month: 6, toponyms: []) }

    before do
      phoenix_tables!
      create(:point, user: user, timestamp: Time.utc(2014, 6, 15).to_i, city: 'Leipzig', country: 'Germany')
      Sidekiq.redis do |redis|
        redis.call('SET', "#{Stats::GeocodedDays::VERSION_KEY_PREFIX}:#{member}", 'redis-version')
        redis.call('ZADD', Stats::GeocodedDays::PENDING_KEY, 1, member)
      end
    end

    after do
      clear_geocoded_days
      Sidekiq.redis do |redis|
        redis.del(Stats::ToponymsRefresh::CURSOR_KEY, Stats::ToponymsRefresh::DISCOVERY_KEY,
                  Stats::ToponymsRefresh::TURN_KEY)
      end
    end

    it 'drains the Redis day into the queue and refreshes it in the same run' do
      PhoenixCursors.set(Stats::ToponymsRefresh::TURN_KEY, 1)

      described_class.perform_now

      expect(stat.reload.toponyms.first['country']).to eq('Germany')
      expect(Stats::GeocodedDays.due(limit: 10)).to be_empty
      expect(Sidekiq.redis { |redis| redis.call('ZCARD', Stats::GeocodedDays::PENDING_KEY) }).to eq(0)
    end

    it 'Oban-owned: still drains the Redis day into the queue, then leaves the run to Phoenix' do
      job_owner!(described_class::OWNER_KEY, :oban)
      allow(Stats::ToponymsRefresh).to receive(:new)

      described_class.perform_now

      expect(ActiveRecord::Base.connection.select_values('SELECT member FROM phoenix.stats_geocoded_days'))
        .to eq([member])
      expect(Sidekiq.redis { |redis| redis.call('ZCARD', Stats::GeocodedDays::PENDING_KEY) }).to eq(0)
      expect(Stats::ToponymsRefresh).not_to have_received(:new)
    end
  end
end

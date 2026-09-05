# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Stats::GeocodedDays do
  include ActiveSupport::Testing::TimeHelpers
  let(:user) { create(:user, settings: { 'timezone' => 'Asia/Tokyo' }) }
  let(:timestamp) { Time.utc(2014, 12, 31, 23, 30).to_i }

  before { clear_geocoded_days }
  after { clear_geocoded_days }

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
  it 'keeps pending snapshots optional when Redis is unavailable' do
    account = user
    allow(Sidekiq).to receive(:redis).and_raise(RedisClient::CannotConnectError, 'unavailable')
    expect(described_class.snapshot_month(account, 2015, 1)).to eq({})
  ensure
    allow(Sidekiq).to receive(:redis).and_call_original
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Stats::ToponymsRefresh do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user, settings: { 'timezone' => 'Etc/UTC', 'min_minutes_spent_in_city' => 0 }) }

  before do
    clear_geocoded_days
    Sidekiq.redis do |r|
      r.del(described_class::CURSOR_KEY,
            described_class::DISCOVERY_KEY, described_class::TURN_KEY)
    end
  end

  after do
    clear_geocoded_days
    Sidekiq.redis do |r|
      r.del(described_class::CURSOR_KEY,
            described_class::DISCOVERY_KEY, described_class::TURN_KEY)
    end
  end

  it 'bounds historical repair globally and advances through existing statistics' do
    stats = (1..5).map do |month|
      create(:point, user: user, timestamp: Time.utc(2014, month, 15).to_i, city: 'Berlin', country: 'Germany')
      create(:stat, user: user, year: 2014, month: month, toponyms: [])
    end
    Sidekiq.redis { |r| r.set(described_class::CURSOR_KEY, stats.first.id - 1) }
    described_class.new.call
    expect(stats.count { |stat| stat.reload.toponyms.present? }).to eq(2)
    described_class.new.call
    expect(stats.count { |stat| stat.reload.toponyms.present? }).to eq(4)
    described_class.new.call
    expect(stats.count { |stat| stat.reload.toponyms.present? }).to eq(5)
  end

  it 'retains pending work after a failed refresh and succeeds on retry' do
    point = create(:point, user: user, timestamp: Time.utc(2014, 6, 15).to_i, city: 'Berlin', country: 'Germany')
    stat = create(:stat, user: user, year: 2014, month: 6, toponyms: [])
    Stats::GeocodedDays.mark(user.id, point.timestamp)
    allow(Stats::Toponyms).to receive(:new).and_raise(IOError, 'calculation unavailable')
    travel 61.minutes do
      described_class.new.call
      expect(stat.reload.toponyms).to be_empty
    end
    allow(Stats::Toponyms).to receive(:new).and_call_original
    travel 122.minutes do
      expect(Stats::GeocodedDays.due(limit: 10)).not_to be_empty
      described_class.new.call
      expect(stat.reload.toponyms.first['country']).to eq('Germany')
      expect(Stats::GeocodedDays.due(limit: 10)).to be_empty
    end
  end

  it 'schedules complete statistics when the month does not yet exist' do
    point = create(:point, user: user, timestamp: Time.utc(2014, 6, 15).to_i)
    Sidekiq.redis { |r| r.set(described_class::DISCOVERY_KEY, [user.id + 1, 0].to_json) }
    Stats::GeocodedDays.mark(user.id, point.timestamp)
    travel 61.minutes do
      expect { described_class.new.call }
        .to have_enqueued_job(Stats::CalculatingJob).with(user.id, 2014, 6, notify_on_failure: false)
      expect(user.stats.where(year: 2014, month: 6)).not_to exist
    end
  end
  it 'discovers a historical month even when both its stats and notification are absent' do
    create(:point, user: user, timestamp: Time.utc(2014, 6, 15).to_i,
                   city: 'Berlin', country: 'Germany', reverse_geocoded_at: Time.current)
    Sidekiq.redis { |r| r.set(described_class::DISCOVERY_KEY, [user.id, 0].to_json) }
    expect { described_class.new.call }
      .to have_enqueued_job(Stats::CalculatingJob).with(user.id, 2014, 6, notify_on_failure: false)
  end
  it 'coalesces full calculation requests for many days in one missing month' do
    10.times do |day|
      timestamp = Time.utc(2014, 6, day + 1).to_i
      create(:point, user: user, timestamp: timestamp)
      Stats::GeocodedDays.mark(user.id, timestamp)
    end
    Sidekiq.redis { |r| r.set(described_class::DISCOVERY_KEY, [user.id, 0].to_json) }
    travel 61.minutes do
      expect { described_class.new.call }
        .to have_enqueued_job(Stats::CalculatingJob).with(user.id, 2014, 6, notify_on_failure: false).exactly(:once)
    end
  end
end

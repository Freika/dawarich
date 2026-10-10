# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Stats::ToponymsRefresh do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user, settings: { 'timezone' => 'Etc/UTC', 'min_minutes_spent_in_city' => 0 }) }

  before do
    clear_geocoded_days
    [described_class::CURSOR_KEY, described_class::DISCOVERY_KEY, described_class::TURN_KEY]
      .each { PhoenixCursors.del(_1) }
  end

  after do
    clear_geocoded_days
    [described_class::CURSOR_KEY, described_class::DISCOVERY_KEY, described_class::TURN_KEY]
      .each { PhoenixCursors.del(_1) }
  end

  it 'bounds historical repair globally and advances through existing statistics' do
    stats = (1..5).map do |month|
      create(:point, user: user, timestamp: Time.utc(2014, month, 15).to_i, city: 'Berlin', country: 'Germany')
      create(:stat, user: user, year: 2014, month: month, toponyms: [])
    end
    PhoenixCursors.set(described_class::CURSOR_KEY, stats.first.id - 1)
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
    PhoenixCursors.set(described_class::DISCOVERY_KEY, [user.id + 1, 0].to_json)
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
    PhoenixCursors.set(described_class::DISCOVERY_KEY, [user.id, 0].to_json)
    expect { described_class.new.call }
      .to have_enqueued_job(Stats::CalculatingJob).with(user.id, 2014, 6, notify_on_failure: false)
  end
  it 'coalesces full calculation requests for many days in one missing month' do
    10.times do |day|
      timestamp = Time.utc(2014, 6, day + 1).to_i
      create(:point, user: user, timestamp: timestamp)
      Stats::GeocodedDays.mark(user.id, timestamp)
    end
    PhoenixCursors.set(described_class::DISCOVERY_KEY, [user.id, 0].to_json)
    travel 61.minutes do
      expect { described_class.new.call }
        .to have_enqueued_job(Stats::CalculatingJob).with(user.id, 2014, 6, notify_on_failure: false).exactly(:once)
    end
  end

  context 'with phoenix.cursors and phoenix.stats_geocoded_days' do
    before { phoenix_tables! }

    it 'keeps the turn and both cursors in phoenix.cursors and never touches their Redis keys' do
      stats = (1..3).map do |month|
        create(:point, user: user, timestamp: Time.utc(2014, month, 15).to_i, city: 'Leipzig', country: 'Germany')
        create(:stat, user: user, year: 2014, month: month, toponyms: [])
      end
      PhoenixCursors.set(described_class::CURSOR_KEY, stats.first.id - 1)

      described_class.new.call

      expect(stats.count { |stat| stat.reload.toponyms.present? }).to eq(2)
      expect(ActiveRecord::Base.connection.select_rows('SELECT key, value FROM phoenix.cursors ORDER BY key').to_h)
        .to eq(described_class::CURSOR_KEY => stats.second.id.to_s,
               described_class::DISCOVERY_KEY => [user.id, Time.utc(2014, 2, 1).to_i].to_json,
               described_class::TURN_KEY => '1')
      expect(Sidekiq.redis do |r|
        r.exists(described_class::CURSOR_KEY, described_class::DISCOVERY_KEY, described_class::TURN_KEY)
      end).to eq(0)
    end
  end

  it 'skips the run while another holder keeps the refresh lease, and runs once it is released' do
    phoenix_leases!
    connection = ActiveRecord::Base.connection
    connection.execute(
      'INSERT INTO phoenix.leases (name, holder, expires_at) ' \
      "VALUES ('stats:toponyms_refresh', 'other', statement_timestamp() + interval '60 seconds')"
    )
    turn = -> { PhoenixCursors.get(described_class::TURN_KEY) }

    expect { described_class.new.call }.not_to(change { turn.call })
    connection.execute("DELETE FROM phoenix.leases WHERE name = 'stats:toponyms_refresh'")
    expect { described_class.new.call }.to(change { turn.call })
    expect(connection.select_value('SELECT count(*) FROM phoenix.leases').to_i).to eq(0)
  end
end

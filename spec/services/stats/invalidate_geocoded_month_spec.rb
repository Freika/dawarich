# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Stats::InvalidateGeocodedMonth do
  let(:user) { create(:user, settings: { 'timezone' => 'Asia/Tokyo' }) }
  let(:point) { create(:point, user:, timestamp: Time.utc(2014, 12, 31, 23, 30).to_i) }

  it 'invalidates the account-local month across the year boundary' do
    december = create(:stat, user:, year: 2014, month: 12, calculation_version: 1)
    january = create(:stat, user:, year: 2015, month: 1, calculation_version: 1)

    described_class.call(point)

    expect(january.reload.calculation_version).to eq(0)
    expect(december.reload.calculation_version).to eq(1)
  end

  it 'coalesces repeated invalidations into one stats update' do
    stat = create(:stat, user:, year: 2015, month: 1, calculation_version: 1)
    point.id
    updates = []
    subscriber = lambda do |*args|
      sql = args.last[:sql]
      updates << sql if sql.match?(/UPDATE "stats"/)
    end

    ActiveSupport::Notifications.subscribed(subscriber, 'sql.active_record') do
      10.times { described_class.call(point) }
    end

    expect(stat.reload.calculation_version).to eq(0)
    expect(updates.size).to eq(1)
  end

  it 'leaves a new month eligible for repair if initial statistics are not ready' do
    expect { described_class.call(point) }.to change { user.stats.count }.by(1)
    stat = user.stats.find_by!(year: 2015, month: 1)
    expect(stat.calculation_version).to eq(0)
    expect(stat.distance).to eq(0)
  end

  it 'does not invalidate another user statistics' do
    other = create(:stat, year: 2015, month: 1, calculation_version: 1)

    described_class.call(point)

    expect(other.reload.calculation_version).to eq(1)
  end
end

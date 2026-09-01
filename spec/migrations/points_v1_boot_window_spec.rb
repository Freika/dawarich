# frozen_string_literal: true

require 'rails_helper'

# Self-hosted instances run the NEW code against the OLD table for the whole
# copy: Sidekiq keeps ingesting while the migration walks. Everything that
# touches points must work in that window.
RSpec.describe 'new code on a v1-shaped points table', :non_transactional do
  let(:connection) { ActiveRecord::Base.connection }
  let!(:user) { create(:user) }
  let(:payload) do
    {
      locations: [
        {
          type: 'Feature',
          geometry: { type: 'Point', coordinates: [12.3712, 51.3402] },
          properties: {
            timestamp: '2026-04-15T10:00:00Z',
            device_id: 'boot-device',
            battery_state: 'unplugged',
            battery_level: 0.8,
            wifi: 'home',
            speed: 3.5,
            altitude: 112.25
          }
        }
      ]
    }
  end

  before { PointsV1Schema.install_v1_points }

  # Non-transactional: take the user's rows and the Redis keys ingest left
  # behind with us, so later specs that reuse the user id start clean.
  after do
    PointsV1Schema.restore_real_points
    Tracks::BackfillScheduler.pop_range(user.id)
    Tracks::RealtimeDebouncer.new(user.id).clear
    Visits::RealtimeDebouncer.new(user.id).clear
    user.destroy
    Stat.where(user_id: user.id).delete_all
    Notification.where(user_id: user.id).delete_all
  end

  it 'ignores the dropped columns even though the table still has them' do
    expect(Point.column_names).not_to include('country_name', 'tracker_id', 'altitude_decimal', 'mode')
    expect(connection.column_exists?(:points, :country_name)).to be(true)
  end

  it 'ingests through the resolver, leaving the legacy columns untouched' do
    Points::Create.new(user, payload).call

    row = connection.select_one('SELECT source_id, tracker_id, battery_status, altitude FROM points')
    expect(row['source_id']).to be_present
    expect(row['tracker_id']).to be_nil
    expect(row['battery_status']).to be_nil
    expect(row['altitude']).to eq(112)
  end

  it 'reads the device combo, serializes and lists points' do
    Points::Create.new(user, payload).call
    point = user.points.preload(:source).first

    expect(point.tracker_id).to eq('boot-device')
    expect(point.battery_status).to eq('unplugged')
    expect(Api::PointSerializer.new(point).call).to include('tracker_id' => 'boot-device', 'country_name' => '')
    expect(Points::SlimCollectionQuery.new(user.points).call.first).to include(tracker_id: 'boot-device')
  end

  it 'calculates monthly stats' do
    Points::Create.new(user, payload).call

    expect { Stats::CalculateMonth.new(user.id, 2026, 4).call }.not_to raise_error
    expect(user.stats.find_by(year: 2026, month: 4)).to be_present
  end
end

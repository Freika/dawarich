# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Visit detection across a smart tracking pause' do
  let(:user) { create(:user) }
  let(:arrived_at) { Time.utc(2026, 10, 10, 11, 50) }
  let(:paused_at) { arrived_at + 10.minutes }
  let(:resumed_at) { paused_at + 90.minutes }
  # Synthetic positions in the open South Pacific, far from any real venue.
  let(:latitude) { -48.123456 }
  let(:longitude) { -123.456789 }

  before do
    allow(DawarichSettings).to receive_messages(reverse_geocoding_enabled?: false, store_geodata?: false)
    allow(Geocoder).to receive(:search).and_return([])
  end

  def fix(time, north_meters, stationary_presence: false)
    create(:point, user:, latitude: latitude + (north_meters / 111_195.0), longitude:,
                   timestamp: time.to_i, accuracy: 5,
                   motion_data: stationary_presence ? { 'action' => 'stationary_presence' } : {})
  end

  # Arrival with a 50 m distance filter, then the app's presence reports while
  # it waits to pause, the last of which is the stop anchor taken just before
  # GPS goes off.
  def arrive_and_pause(stationary_presence: true)
    arrival = [fix(arrived_at - 2.minutes, -110), fix(arrived_at - 1.minute, -55), fix(arrived_at, 0)]
    presence = (1..5).map { |i| fix(arrived_at + (i * 2).minutes, 2, stationary_presence:) }
    arrival + presence
  end

  # Tracking resumes only once the wake geofence is crossed.
  def leave(from_north_meters)
    (0..2).map { |i| fix(resumed_at + i.minutes, from_north_meters + (i * 55)) }
  end

  def detect
    Visits::SmartDetect.new(user, start_at: arrived_at - 1.hour, end_at: resumed_at + 1.hour).call
  end

  it 'counts the pause as part of the stay when tracking resumes at the wake geofence' do
    stay = arrive_and_pause
    departure = leave(120)

    visits = detect

    expect(visits.size).to eq(1)
    expect(visits.first.started_at).to be <= arrived_at
    expect(visits.first.ended_at).to eq(resumed_at)
    expect(stay.map { |point| point.reload.visit_id }.uniq).to eq([visits.first.id])
    # The way out is movement, not part of the stay.
    expect(departure.map { |point| point.reload.visit_id }).to all(be_nil)
  end

  it 'does not bridge a pause that the app did not report as a stop' do
    arrive_and_pause(stationary_presence: false)
    leave(120)

    expect(detect.map(&:ended_at)).to all(be <= paused_at)
  end

  it 'does not bridge a pause that ends far from where it began' do
    arrive_and_pause
    leave(5_000)

    expect(detect.map(&:ended_at)).to all(be <= paused_at)
  end
end

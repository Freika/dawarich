# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Visit across a tracking pause at the same location' do
  let(:user) { create(:user) }
  let(:arrival) { Time.zone.parse('2026-10-10 16:00:00 UTC') }

  before do
    allow(DawarichSettings).to receive_messages(reverse_geocoding_enabled?: false, store_geodata?: false)
    allow(Geocoder).to receive(:search).and_return([])
  end

  it 'creates a visit between identical arrival and departure fixes despite nearby approach and exit fixes' do
    # Made-up coordinates in the open ocean. Each side has less than the
    # default five-minute dwell; the 90-minute tracking silence is the stay.
    # The endpoint of the approach is exactly the start point of the exit.
    samples = [
      [-180, -100], [-120, -80], [-60, -60], [0, 0],
      [5400, 0], [5460, 60], [5520, 80], [5580, 100]
    ]
    points = samples.map do |seconds, north_meters|
      latitude = -48.123456 + north_meters / 111_195.0
      create(:point, user: user, latitude: latitude, longitude: -123.456789,
                     timestamp: arrival.to_i + seconds, accuracy: 5)
    end

    visits = Visits::SmartDetect.new(
      user, start_at: arrival - 10.minutes, end_at: arrival + 2.hours
    ).call

    expect(visits.size).to eq(1)
    expect(visits.first.started_at).to be <= arrival
    expect(visits.first.ended_at).to be >= arrival + 90.minutes
    expect(user.visits.count).to eq(1)
    expect(points.map { |point| point.reload.visit_id }.uniq).to eq([visits.first.id])
  end
end

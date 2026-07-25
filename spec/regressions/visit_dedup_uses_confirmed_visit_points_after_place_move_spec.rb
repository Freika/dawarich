# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Visit re-detection dedup after a confirmed visit place is moved' do
  let(:user) { create(:user) }

  # Coordinates the confirmed visit's points actually cluster around (Leipzig).
  let(:home_lat) { 51.3402 }
  let(:home_lon) { 12.3712 }

  # Place marker dragged far from the points during an address correction (~4 km away).
  let(:moved_place) do
    create(
      :place,
      name: 'Home', user_id: nil,
      latitude: 51.3600, longitude: 12.4200, lonlat: 'POINT(12.4200 51.3600)'
    )
  end

  let!(:confirmed_visit) do
    create(
      :visit,
      user: user, place: moved_place, area: nil, status: :confirmed,
      started_at: 1.5.hours.ago, ended_at: 45.minutes.ago, duration: 45
    )
  end

  before do
    create(:point, user: user, visit: confirmed_visit, lonlat: "POINT(#{home_lon} #{home_lat})")
    create(:point, user: user, visit: confirmed_visit,
                   lonlat: "POINT(#{home_lon + 0.0002} #{home_lat + 0.0002})")

    place_finder = instance_double(Visits::PlaceFinder, find_or_create_place: nil)
    allow(Visits::PlaceFinder).to receive(:new).with(user).and_return(place_finder)
  end

  it 'does not re-suggest a visit for a cluster sitting on the confirmed visit points' do
    candidate = {
      start_time: 1.hour.ago.to_i,
      end_time: 30.minutes.ago.to_i,
      duration: 30.minutes.to_i,
      center_lat: home_lat,
      center_lon: home_lon,
      radius: 50,
      suggested_name: 'Home',
      points: [create(:point, user: user), create(:point, user: user)]
    }

    visits = Visits::Creator.new(user).create_visits([candidate])

    expect(visits).to be_empty
    expect(user.visits.reload.count).to eq(1)
  end
end

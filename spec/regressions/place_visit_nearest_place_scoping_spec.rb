# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Places::Visits::Create do
  let(:user) { create(:user) }
  let(:base_ts) { Time.utc(2024, 5, 1, 12, 0, 0).to_i }

  # ~120m apart along the same latitude. A shared cluster of points sits 40m
  # from `nearest_place` and 80m from `farther_place`, inside both radii.
  let(:base_lat) { 54.2905245 }
  let(:base_lon) { 13.0948638 }
  let(:farther_lon) { base_lon + 0.00184771 } # ~120m east of nearest place
  let(:cluster_lon) { base_lon + 0.00061590 } # ~40m east of nearest place, ~80m from farther

  # Created first so it owns the lower id and scans first.
  let!(:farther_place) do
    create(:place, user: user, latitude: base_lat, longitude: farther_lon,
                   lonlat: "POINT(#{farther_lon} #{base_lat})")
  end
  let!(:nearest_place) do
    create(:place, user: user, latitude: base_lat, longitude: base_lon,
                   lonlat: "POINT(#{base_lon} #{base_lat})")
  end

  def run
    described_class.new(user, user.reload.places, throttle_seconds: 0).call
  end

  def cluster_point(timestamp)
    create(:point, user: user, latitude: base_lat, longitude: cluster_lon,
                   lonlat: "POINT(#{cluster_lon} #{base_lat})", timestamp: timestamp)
  end

  it 'suggests a visit only for the nearest place among overlapping places' do
    cluster_point(base_ts)
    cluster_point(base_ts + 5.minutes)
    cluster_point(base_ts + 10.minutes)

    run

    expect(Visit.where(place_id: nearest_place.id, user_id: user.id)).to exist
    expect(Visit.where(place_id: farther_place.id, user_id: user.id)).to be_empty
    expect(Visit.count).to eq(1)

    visited_ids = Point.where(user_id: user.id).where.not(visit_id: nil).distinct.pluck(:visit_id)
    expect(visited_ids).to contain_exactly(Visit.find_by(place_id: nearest_place.id).id)
  end
end

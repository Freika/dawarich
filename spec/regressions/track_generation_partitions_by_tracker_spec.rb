# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Track generation partitions points by tracker_id' do
  let(:user) do
    create(:user, settings: {
             'minutes_between_routes' => 30,
             'meters_between_routes' => 500
           })
  end
  let(:base_time) { 1.hour.ago.to_i }

  let(:berlin_lon) { 13.405 }
  let(:berlin_lat) { 52.52 }
  let(:paris_lon) { 2.3522 }
  let(:paris_lat) { 48.8566 }

  before do
    10.times do |i|
      create(
        :point,
        user: user,
        tracker_id: 'iphone',
        timestamp: base_time + (i * 60),
        lonlat: "POINT(#{berlin_lon + (i * 0.0001)} #{berlin_lat + (i * 0.0001)})"
      )
      create(
        :point,
        user: user,
        tracker_id: 'watch',
        timestamp: base_time + (i * 60) + 30,
        lonlat: "POINT(#{paris_lon + (i * 0.0001)} #{paris_lat + (i * 0.0001)})"
      )
    end
  end

  it 'produces one track per tracker_id, never connecting Berlin and Paris points' do
    Tracks::IncrementalGenerator.new(user).call

    expect(user.tracks.count).to eq(2)
    expect(user.tracks.pluck(:tracker_id)).to match_array(%w[iphone watch])
  end

  it 'each generated track contains only points from its own tracker_id' do
    Tracks::IncrementalGenerator.new(user).call

    user.tracks.each do |track|
      tracker_ids_in_track = track.points.pluck(:tracker_id).uniq
      expect(tracker_ids_in_track).to eq([track.tracker_id])
    end
  end

  it 'no track distance approaches the Berlin↔Paris geographic separation' do
    Tracks::IncrementalGenerator.new(user).call

    expect(user.tracks.maximum(:distance) || 0).to be < 10_000
  end
end

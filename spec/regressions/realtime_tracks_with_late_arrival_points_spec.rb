# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Real-time track generation with late-arriving GPS points' do
  let(:user) do
    create(:user, settings: {
             'minutes_between_routes' => 30,
             'meters_between_routes' => 500
           })
  end
  let(:generator) { Tracks::IncrementalGenerator.new(user) }
  let(:tracker) { 'colota-device-1' }
  let(:base_time) { 1.hour.ago.to_i }

  def make_point(offset_seconds, lng:, lat:, track: nil, tracker_id: tracker, created_at: nil)
    attrs = {
      user: user,
      timestamp: base_time + offset_seconds,
      lonlat: "POINT(#{lng} #{lat})",
      tracker_id: tracker_id,
      track: track
    }
    attrs[:created_at] = created_at if created_at
    create(:point, **attrs)
  end

  context 'when a single late point arrives inside an existing track time window' do
    let!(:existing_track) do
      create(:track, user: user, tracker_id: tracker,
                     start_at: Time.zone.at(base_time),
                     end_at: Time.zone.at(base_time + 30))
    end

    before do
      make_point(0,  lng: -74.000, lat: 40.7128, track: existing_track)
      make_point(15, lng: -74.001, lat: 40.7138, track: existing_track)
      make_point(30, lng: -74.002, lat: 40.7148, track: existing_track)

      make_point(10, lng: -74.0005, lat: 40.7133,
                     track: nil,
                     created_at: 2.minutes.ago)
    end

    it 'absorbs the orphan point into the existing track' do
      generator.call

      expect(user.tracks.count).to eq(1)
      expect(existing_track.reload.points.count).to eq(4)
    end

    it 'recalculates distance and path to include the absorbed point' do
      pre_distance = existing_track.distance
      pre_path = existing_track.original_path.to_s

      generator.call

      existing_track.reload
      expect(existing_track.distance).to be > 0
      expect(existing_track.distance).not_to eq(pre_distance)
      expect(existing_track.original_path).to be_present
      expect(existing_track.original_path.to_s).not_to eq(pre_path)
    end
  end

  context 'when late points sandwiched between batches form a new track inside an existing window' do
    let!(:existing_track) do
      create(:track, user: user, tracker_id: tracker,
                     start_at: Time.zone.at(base_time),
                     end_at: Time.zone.at(base_time + 30))
    end

    before do
      make_point(0,  lng: -74.000, lat: 40.7128, track: existing_track)
      make_point(15, lng: -74.001, lat: 40.7138, track: existing_track)
      make_point(30, lng: -74.002, lat: 40.7148, track: existing_track)

      make_point(10, lng: -74.0005, lat: 40.7133, track: nil, created_at: 2.minutes.ago)
      make_point(45, lng: -74.003,  lat: 40.7158, track: nil, created_at: 2.minutes.ago)
      make_point(60, lng: -74.004,  lat: 40.7168, track: nil, created_at: 2.minutes.ago)
      make_point(75, lng: -74.005,  lat: 40.7178, track: nil, created_at: 2.minutes.ago)
    end

    it 'produces a single track containing all points in timestamp order' do
      generator.call

      expect(user.tracks.count).to eq(1)
      track = user.tracks.first
      timestamps = track.points.order(:timestamp).pluck(:timestamp)
      expect(timestamps).to eq([base_time, base_time + 10, base_time + 15, base_time + 30,
                                base_time + 45, base_time + 60, base_time + 75])
    end
  end

  context 'when late points straddle an existing track end boundary' do
    let!(:existing_track) do
      create(:track, user: user, tracker_id: tracker,
                     start_at: Time.zone.at(base_time),
                     end_at: Time.zone.at(base_time + 30))
    end

    before do
      make_point(0,  lng: -74.000, lat: 40.7128, track: existing_track)
      make_point(15, lng: -74.001, lat: 40.7138, track: existing_track)
      make_point(30, lng: -74.002, lat: 40.7148, track: existing_track)

      make_point(20, lng: -74.0015, lat: 40.7143, track: nil, created_at: 2.minutes.ago)
      make_point(40, lng: -74.0025, lat: 40.7158, track: nil, created_at: 2.minutes.ago)
      make_point(50, lng: -74.003,  lat: 40.7168, track: nil, created_at: 2.minutes.ago)
    end

    it 'merges the straddling late points with the existing track' do
      generator.call

      expect(user.tracks.count).to eq(1)
      merged = user.tracks.first
      expect(merged.points.count).to eq(6)
      expect(merged.end_at.to_i).to eq(base_time + 50)
    end
  end

  context 'when multiple overlapping tracks already exist for the same tracker' do
    let!(:track_a) do
      create(:track, user: user, tracker_id: tracker,
                     start_at: Time.zone.at(base_time),
                     end_at: Time.zone.at(base_time + 60))
    end
    let!(:track_b) do
      create(:track, user: user, tracker_id: tracker,
                     start_at: Time.zone.at(base_time + 20),
                     end_at: Time.zone.at(base_time + 80))
    end
    let!(:track_c) do
      create(:track, user: user, tracker_id: tracker,
                     start_at: Time.zone.at(base_time + 50),
                     end_at: Time.zone.at(base_time + 100))
    end

    before do
      make_point(0,   lng: -74.000, lat: 40.7128, track: track_a)
      make_point(30,  lng: -74.001, lat: 40.7138, track: track_a)
      make_point(60,  lng: -74.002, lat: 40.7148, track: track_a)
      make_point(20,  lng: -74.0008, lat: 40.7133, track: track_b)
      make_point(50,  lng: -74.0015, lat: 40.7143, track: track_b)
      make_point(80,  lng: -74.003,  lat: 40.7158, track: track_b)
      make_point(50,  lng: -74.0016, lat: 40.7144, track: track_c)
      make_point(70,  lng: -74.0025, lat: 40.7153, track: track_c)
      make_point(100, lng: -74.0035, lat: 40.7163, track: track_c)
    end

    it 'reconciles all three into a single track' do
      generator.call

      expect(user.tracks.count).to eq(1)
      merged = user.tracks.first
      expect(merged.start_at.to_i).to eq(base_time)
      expect(merged.end_at.to_i).to eq(base_time + 100)
    end
  end

  context 'when overlapping tracks have the same tracker_id but spatially distant endpoints' do
    let!(:track_a) do
      create(:track, user: user, tracker_id: tracker,
                     start_at: Time.zone.at(base_time),
                     end_at: Time.zone.at(base_time + 30))
    end
    let!(:track_b) do
      create(:track, user: user, tracker_id: tracker,
                     start_at: Time.zone.at(base_time + 10),
                     end_at: Time.zone.at(base_time + 40))
    end

    before do
      make_point(0,  lng: -74.000, lat: 40.7128, track: track_a)
      make_point(15, lng: -74.001, lat: 40.7138, track: track_a)
      make_point(30, lng: -74.002, lat: 40.7148, track: track_a)
      make_point(10, lng: -73.500, lat: 40.5000, track: track_b)
      make_point(25, lng: -73.501, lat: 40.5010, track: track_b)
      make_point(40, lng: -73.502, lat: 40.5020, track: track_b)
    end

    it 'keeps them separate because the gap exceeds the same-tracker distance cap' do
      generator.call

      expect(user.tracks.count).to eq(2)
    end
  end

  context 'when overlapping tracks have the same tracker_id and endpoints are within the same-tracker cap' do
    let!(:track_a) do
      create(:track, user: user, tracker_id: tracker,
                     start_at: Time.zone.at(base_time),
                     end_at: Time.zone.at(base_time + 30))
    end
    let!(:track_b) do
      create(:track, user: user, tracker_id: tracker,
                     start_at: Time.zone.at(base_time + 10),
                     end_at: Time.zone.at(base_time + 40))
    end

    before do
      make_point(0,  lng: -74.000, lat: 40.7128, track: track_a)
      make_point(15, lng: -74.001, lat: 40.7138, track: track_a)
      make_point(30, lng: -74.002, lat: 40.7148, track: track_a)
      make_point(10, lng: -74.003, lat: 40.7158, track: track_b)
      make_point(25, lng: -74.004, lat: 40.7168, track: track_b)
      make_point(40, lng: -74.005, lat: 40.7178, track: track_b)
    end

    it 'merges them because tracker_id matches and endpoints are close' do
      generator.call

      expect(user.tracks.count).to eq(1)
    end
  end

  context 'when overlapping tracks belong to different trackers' do
    let!(:track_a) do
      create(:track, user: user, tracker_id: 'device-a',
                     start_at: Time.zone.at(base_time),
                     end_at: Time.zone.at(base_time + 30))
    end
    let!(:track_b) do
      create(:track, user: user, tracker_id: 'device-b',
                     start_at: Time.zone.at(base_time + 10),
                     end_at: Time.zone.at(base_time + 40))
    end

    before do
      make_point(0,  lng: -74.000, lat: 40.7128, track: track_a, tracker_id: 'device-a')
      make_point(15, lng: -74.001, lat: 40.7138, track: track_a, tracker_id: 'device-a')
      make_point(30, lng: -74.002, lat: 40.7148, track: track_a, tracker_id: 'device-a')
      make_point(10, lng: -74.5,   lat: 40.50,   track: track_b, tracker_id: 'device-b')
      make_point(25, lng: -74.501, lat: 40.501,  track: track_b, tracker_id: 'device-b')
      make_point(40, lng: -74.502, lat: 40.502,  track: track_b, tracker_id: 'device-b')
    end

    it 'preserves both tracks because they belong to different devices' do
      generator.call

      expect(user.tracks.count).to eq(2)
      expect(user.tracks.pluck(:tracker_id)).to contain_exactly('device-a', 'device-b')
    end
  end

  context 'when an untracked point is too fresh (still inside the anomaly-filter race window)' do
    let!(:existing_track) do
      create(:track, user: user, tracker_id: tracker,
                     start_at: Time.zone.at(base_time),
                     end_at: Time.zone.at(base_time + 30))
    end

    before do
      make_point(0,  lng: -74.000, lat: 40.7128, track: existing_track)
      make_point(30, lng: -74.002, lat: 40.7148, track: existing_track)

      make_point(15, lng: -74.001, lat: 40.7138,
                     track: nil,
                     created_at: 10.seconds.ago)
    end

    it 'leaves the fresh point untracked until anomaly detection completes' do
      generator.call

      expect(existing_track.reload.points.count).to eq(2)
      expect(user.points.where(track_id: nil).count).to eq(1)
    end
  end

  context 'when an untracked point is flagged as anomaly' do
    let!(:existing_track) do
      create(:track, user: user, tracker_id: tracker,
                     start_at: Time.zone.at(base_time),
                     end_at: Time.zone.at(base_time + 30))
    end

    before do
      make_point(0,  lng: -74.000, lat: 40.7128, track: existing_track)
      make_point(30, lng: -74.002, lat: 40.7148, track: existing_track)

      anomaly = make_point(15, lng: -74.001, lat: 40.7138, track: nil, created_at: 2.minutes.ago)
      anomaly.update_column(:anomaly, true)
    end

    it 'does not absorb the anomaly point' do
      generator.call

      expect(existing_track.reload.points.count).to eq(2)
      expect(user.points.where(track_id: nil, anomaly: true).count).to eq(1)
    end
  end
end

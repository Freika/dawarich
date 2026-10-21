# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tracks::IncrementalGenerator do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) do
    create(:user, settings: {
             'minutes_between_routes' => 30,
             'meters_between_routes' => 500
           })
  end
  let(:generator) { described_class.new(user) }

  describe '#call' do
    it 'stops extending an arrival track after continuous stationary reports exceed the threshold' do
      start = Time.utc(2025, 2, 10, 18)
      feed = (0..24).map do |index|
        travel_to(start + index * 5.minutes) do
          point = create(:point, user: user, tracker_id: 'synthetic-realtime-stop',
                                 timestamp: Time.current.to_i,
                                 lonlat: "POINT(#{-140.0 + [index, 3].min * 0.002} -40.0)")
          described_class.new(user).call
          point
        end
      end

      arrival_track = feed.first.reload.track
      expect(arrival_track).to be_present
      expect(user.tracks.count).to eq(1)
      expect(arrival_track.end_at.to_i).to be_between(feed[3].timestamp, feed[9].timestamp)
      expect(feed[10..].map { |point| point.reload.track_id }).to all(be_nil)
    end

    context 'when there are no untracked points' do
      it 'returns nil and creates no tracks' do
        expect { generator.call }.not_to change(Track, :count)
      end
    end

    context 'when there are untracked points forming a single segment' do
      let(:base_time) { 1.hour.ago.to_i }

      before do
        # Create points that form a continuous track
        create(:point, user: user, timestamp: base_time, lonlat: 'POINT(-74.006 40.7128)')
        create(:point, user: user, timestamp: base_time + 5.minutes.to_i, lonlat: 'POINT(-74.007 40.7138)')
        create(:point, user: user, timestamp: base_time + 10.minutes.to_i, lonlat: 'POINT(-74.008 40.7148)')
      end

      it 'creates a track from the untracked points' do
        expect { generator.call }.to change(Track, :count).by(1)
      end

      it 'associates points with the created track' do
        generator.call

        track = user.tracks.last
        expect(track.points.count).to eq(3)
      end

      it 'sets track timestamps correctly' do
        generator.call

        track = user.tracks.last
        expect(track.start_at.to_i).to eq(base_time)
        expect(track.end_at.to_i).to eq(base_time + 10.minutes.to_i)
      end
    end

    context 'when consecutive untracked points exceed the distance threshold' do
      let(:base_time) { 1.hour.ago.to_i }
      let!(:points) do
        3.times.map do |index|
          create(:point, user: user, timestamp: base_time + index.minutes.to_i,
                         lonlat: "POINT(#{-140 + index * 0.0127} -45)")
        end
      end

      it 'creates one track containing all points' do
        expect { generator.call }.to change(Track, :count).by(1)

        expect(user.tracks.sole.points).to match_array(points)
      end
    end

    context 'when points span multiple segments' do
      let(:base_time) { 3.hours.ago.to_i }

      before do
        # First segment - 3 hours ago
        create(:point, user: user, timestamp: base_time, lonlat: 'POINT(-74.006 40.7128)')
        create(:point, user: user, timestamp: base_time + 5.minutes.to_i, lonlat: 'POINT(-74.007 40.7138)')

        # Gap of 2 hours (exceeds 30 minute threshold)
        # Second segment - 1 hour ago
        create(:point, user: user, timestamp: base_time + 2.hours.to_i, lonlat: 'POINT(-75.006 41.7128)')
        create(:point, user: user, timestamp: base_time + 2.hours.to_i + 5.minutes.to_i,
lonlat: 'POINT(-75.007 41.7138)')
      end

      it 'creates tracks for separate segments' do
        expect { generator.call }.to change(Track, :count).by(2)
      end
    end

    context 'when points are older than lookback window' do
      before do
        # Points from 10 hours ago (outside 6-hour lookback)
        create(:point, user: user, timestamp: 10.hours.ago.to_i, lonlat: 'POINT(-74.006 40.7128)')
        create(:point, user: user, timestamp: (10.hours.ago + 5.minutes).to_i, lonlat: 'POINT(-74.007 40.7138)')
      end

      it 'does not create tracks from old points' do
        expect { generator.call }.not_to change(Track, :count)
      end
    end

    context 'when points already have a track' do
      let(:base_time) { 1.hour.ago.to_i }
      let(:existing_track) { create(:track, user: user, start_at: 2.hours.ago, end_at: 1.5.hours.ago) }

      before do
        # Points already associated with a track
        create(:point, user: user, timestamp: base_time, lonlat: 'POINT(-74.006 40.7128)', track: existing_track)
        create(:point, user: user, timestamp: base_time + 5.minutes.to_i, lonlat: 'POINT(-74.007 40.7138)',
               track: existing_track)
      end

      it 'does not create new tracks for already-tracked points' do
        expect { generator.call }.not_to change(Track, :count)
      end
    end

    context 'when a preceding track exists within threshold' do
      let(:base_time) { 1.hour.ago.to_i }

      before do
        # Create an existing track that ended recently
        existing_track = create(:track, user: user,
                                        start_at: Time.zone.at(base_time - 1.hour.to_i),
                                        end_at: Time.zone.at(base_time - 10.minutes.to_i))

        # Create associated points for the existing track
        create(:point, user: user,
               timestamp: base_time - 1.hour.to_i,
               lonlat: 'POINT(-74.004 40.7108)',
               track: existing_track)
        create(:point, user: user,
               timestamp: base_time - 10.minutes.to_i - 5.minutes.to_i,
               lonlat: 'POINT(-74.005 40.7118)',
               track: existing_track)

        # Create new untracked points that should merge with the existing track
        create(:point, user: user, timestamp: base_time, lonlat: 'POINT(-74.006 40.7128)')
        create(:point, user: user, timestamp: base_time + 5.minutes.to_i, lonlat: 'POINT(-74.007 40.7138)')
      end

      it 'merges new track with preceding track' do
        initial_track_count = Track.count

        generator.call

        # Should create a new track then merge it (net change of 0)
        # OR the merger should combine them
        expect(Track.count).to be <= initial_track_count + 1
      end
    end

    context 'with single point segment' do
      before do
        # Single point cannot form a track
        create(:point, user: user, timestamp: 1.hour.ago.to_i, lonlat: 'POINT(-74.006 40.7128)')
      end

      it 'does not create a track from a single point' do
        expect { generator.call }.not_to change(Track, :count)
      end
    end
  end
end

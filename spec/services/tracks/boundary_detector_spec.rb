# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tracks::BoundaryDetector do
  let(:user) { create(:user) }
  let(:detector) { described_class.new(user) }

  before do
    # Stub user settings
    allow(user.safe_settings).to receive(:minutes_between_routes).and_return(30)
    allow(user.safe_settings).to receive(:meters_between_routes).and_return(500)
    
    # Stub Geocoder for consistent distance calculations
    allow_any_instance_of(Point).to receive(:distance_to_geocoder).and_return(100) # 100 meters
    allow(Point).to receive(:calculate_distance_for_array_geocoder).and_return(1000) # 1000 meters
  end

  describe '#initialize' do
    it 'sets the user' do
      expect(detector.user).to eq(user)
    end
  end

  describe '#resolve_cross_chunk_tracks' do
    context 'when no recent tracks exist' do
      it 'returns 0' do
        expect(detector.resolve_cross_chunk_tracks).to eq(0)
      end

      it 'logs no boundary candidates found' do
        expect(Rails.logger).to receive(:info).with(/Resolved 0 boundary tracks/)
        detector.resolve_cross_chunk_tracks
      end
    end

    context 'when no boundary candidates are found' do
      let!(:track1) { create(:track, user: user, created_at: 30.minutes.ago) }
      let!(:track2) { create(:track, user: user, created_at: 25.minutes.ago) }

      before do
        # Create points that are far apart (no spatial connection)
        create(:point, user: user, track: track1, latitude: 40.0, longitude: -74.0, timestamp: 2.hours.ago.to_i)
        create(:point, user: user, track: track2, latitude: 41.0, longitude: -73.0, timestamp: 1.hour.ago.to_i)
        
        # Mock distance to be greater than threshold
        allow_any_instance_of(Point).to receive(:distance_to_geocoder).and_return(1000) # 1000 meters > 500 threshold
      end

      it 'returns 0' do
        expect(detector.resolve_cross_chunk_tracks).to eq(0)
      end
    end

    context 'when boundary candidates exist' do
      let!(:track1) { create(:track, user: user, created_at: 30.minutes.ago, start_at: 2.hours.ago, end_at: 1.5.hours.ago) }
      let!(:track2) { create(:track, user: user, created_at: 25.minutes.ago, start_at: 1.hour.ago, end_at: 30.minutes.ago) }

      let!(:point1_start) { create(:point, user: user, track: track1, latitude: 40.0, longitude: -74.0, timestamp: 2.hours.ago.to_i) }
      let!(:point1_end) { create(:point, user: user, track: track1, latitude: 40.01, longitude: -74.01, timestamp: 1.5.hours.ago.to_i) }
      let!(:point2_start) { create(:point, user: user, track: track2, latitude: 40.01, longitude: -74.01, timestamp: 1.hour.ago.to_i) }
      let!(:point2_end) { create(:point, user: user, track: track2, latitude: 40.02, longitude: -74.02, timestamp: 30.minutes.ago.to_i) }

      before do
        # Mock close distance for connected tracks
        allow_any_instance_of(Point).to receive(:distance_to_geocoder).and_return(100) # Within 500m threshold
      end

      it 'finds and resolves boundary tracks' do
        expect(detector.resolve_cross_chunk_tracks).to eq(1)
      end

      it 'logs the operation' do
        expect(Rails.logger).to receive(:debug).with(/Found \d+ boundary track candidates/)
        expect(Rails.logger).to receive(:info).with(/Resolved 1 boundary tracks/)
        detector.resolve_cross_chunk_tracks
      end

      it 'creates a merged track with all points' do
        expect {
          detector.resolve_cross_chunk_tracks
        }.to change { user.tracks.count }.by(-1) # 2 tracks become 1
        
        merged_track = user.tracks.first
        expect(merged_track.points.count).to eq(4) # All points from both tracks
      end

      it 'deletes original tracks' do
        original_track_ids = [track1.id, track2.id]
        
        detector.resolve_cross_chunk_tracks
        
        expect(Track.where(id: original_track_ids)).to be_empty
      end

      it 'logs track deletion and creation' do
        expect(Rails.logger).to receive(:debug).with(/Deleting boundary track #{track1.id}/)
        expect(Rails.logger).to receive(:debug).with(/Deleting boundary track #{track2.id}/)
        expect(Rails.logger).to receive(:info).with(/Created merged boundary track \d+/)
        
        detector.resolve_cross_chunk_tracks
      end
    end

    context 'when merge fails' do
      let!(:track1) { create(:track, user: user, created_at: 30.minutes.ago) }
      let!(:track2) { create(:track, user: user, created_at: 25.minutes.ago) }

      before do
        # Mock tracks as connected
        allow(detector).to receive(:find_boundary_track_candidates).and_return([[track1, track2]])
        
        # Mock merge failure
        allow(detector).to receive(:create_track_from_points).and_return(nil)
      end

      it 'returns 0 and logs warning' do
        expect(Rails.logger).to receive(:warn).with(/Failed to create merged boundary track/)
        expect(detector.resolve_cross_chunk_tracks).to eq(0)
      end

      it 'does not delete original tracks' do
        detector.resolve_cross_chunk_tracks
        expect(Track.exists?(track1.id)).to be true
        expect(Track.exists?(track2.id)).to be true
      end
    end
  end

  describe 'private methods' do
    describe '#find_connected_tracks' do
      let!(:base_track) { create(:track, user: user, start_at: 2.hours.ago, end_at: 1.5.hours.ago) }
      let!(:connected_track) { create(:track, user: user, start_at: 1.hour.ago, end_at: 30.minutes.ago) }
      let!(:distant_track) { create(:track, user: user, start_at: 5.hours.ago, end_at: 4.hours.ago) }

      let!(:base_point_end) { create(:point, user: user, track: base_track, timestamp: 1.5.hours.ago.to_i) }
      let!(:connected_point_start) { create(:point, user: user, track: connected_track, timestamp: 1.hour.ago.to_i) }
      let!(:distant_point) { create(:point, user: user, track: distant_track, timestamp: 4.hours.ago.to_i) }

      let(:all_tracks) { [base_track, connected_track, distant_track] }

      before do
        # Mock distance for spatially connected tracks
        allow(base_point_end).to receive(:distance_to_geocoder).with(connected_point_start, :m).and_return(100)
        allow(base_point_end).to receive(:distance_to_geocoder).with(distant_point, :m).and_return(2000)
      end

      it 'finds temporally and spatially connected tracks' do
        connected = detector.send(:find_connected_tracks, base_track, all_tracks)
        expect(connected).to include(connected_track)
        expect(connected).not_to include(distant_track)
      end

      it 'excludes the base track itself' do
        connected = detector.send(:find_connected_tracks, base_track, all_tracks)
        expect(connected).not_to include(base_track)
      end

      it 'handles tracks with no points' do
        track_no_points = create(:track, user: user, start_at: 1.hour.ago, end_at: 30.minutes.ago)
        all_tracks_with_empty = all_tracks + [track_no_points]
        
        expect {
          detector.send(:find_connected_tracks, base_track, all_tracks_with_empty)
        }.not_to raise_error
      end
    end

    describe '#tracks_spatially_connected?' do
      let!(:track1) { create(:track, user: user) }
      let!(:track2) { create(:track, user: user) }

      context 'when tracks have no points' do
        it 'returns false' do
          result = detector.send(:tracks_spatially_connected?, track1, track2)
          expect(result).to be false
        end
      end

      context 'when tracks have points' do
        let!(:track1_start) { create(:point, user: user, track: track1, timestamp: 2.hours.ago.to_i) }
        let!(:track1_end) { create(:point, user: user, track: track1, timestamp: 1.5.hours.ago.to_i) }
        let!(:track2_start) { create(:point, user: user, track: track2, timestamp: 1.hour.ago.to_i) }
        let!(:track2_end) { create(:point, user: user, track: track2, timestamp: 30.minutes.ago.to_i) }

        context 'when track1 end connects to track2 start' do
          before do
            allow(track1_end).to receive(:distance_to_geocoder).with(track2_start, :m).and_return(100)
            allow_any_instance_of(Point).to receive(:distance_to_geocoder).and_return(1000) # Default large distance
            allow(track1_end).to receive(:distance_to_geocoder).with(track2_start, :m).and_return(100) # Override for specific connection
          end

          it 'returns true' do
            result = detector.send(:tracks_spatially_connected?, track1, track2)
            expect(result).to be true
          end
        end

        context 'when tracks are not spatially connected' do
          before do
            allow_any_instance_of(Point).to receive(:distance_to_geocoder).and_return(1000) # All points far apart
          end

          it 'returns false' do
            result = detector.send(:tracks_spatially_connected?, track1, track2)
            expect(result).to be false
          end
        end
      end
    end

    describe '#points_are_close?' do
      let(:point1) { create(:point, user: user) }
      let(:point2) { create(:point, user: user) }
      let(:threshold) { 500 }

      it 'returns true when points are within threshold' do
        allow(point1).to receive(:distance_to_geocoder).with(point2, :m).and_return(300)
        
        result = detector.send(:points_are_close?, point1, point2, threshold)
        expect(result).to be true
      end

      it 'returns false when points exceed threshold' do
        allow(point1).to receive(:distance_to_geocoder).with(point2, :m).and_return(700)
        
        result = detector.send(:points_are_close?, point1, point2, threshold)
        expect(result).to be false
      end

      it 'returns false when points are nil' do
        result = detector.send(:points_are_close?, nil, point2, threshold)
        expect(result).to be false
        
        result = detector.send(:points_are_close?, point1, nil, threshold)
        expect(result).to be false
      end
    end

    describe '#valid_boundary_group?' do
      let!(:track1) { create(:track, user: user, start_at: 3.hours.ago, end_at: 2.hours.ago) }
      let!(:track2) { create(:track, user: user, start_at: 1.5.hours.ago, end_at: 1.hour.ago) }
      let!(:track3) { create(:track, user: user, start_at: 45.minutes.ago, end_at: 30.minutes.ago) }

      it 'returns false for single track groups' do
        result = detector.send(:valid_boundary_group?, [track1])
        expect(result).to be false
      end

      it 'returns true for valid sequential groups' do
        result = detector.send(:valid_boundary_group?, [track1, track2, track3])
        expect(result).to be true
      end

      it 'returns false for groups with large time gaps' do
        distant_track = create(:track, user: user, start_at: 10.hours.ago, end_at: 9.hours.ago)
        result = detector.send(:valid_boundary_group?, [distant_track, track1])
        expect(result).to be false
      end
    end

    describe '#merge_boundary_tracks' do
      let!(:track1) { create(:track, user: user, start_at: 2.hours.ago, end_at: 1.5.hours.ago) }
      let!(:track2) { create(:track, user: user, start_at: 1.hour.ago, end_at: 30.minutes.ago) }

      let!(:point1) { create(:point, user: user, track: track1, timestamp: 2.hours.ago.to_i) }
      let!(:point2) { create(:point, user: user, track: track1, timestamp: 1.5.hours.ago.to_i) }
      let!(:point3) { create(:point, user: user, track: track2, timestamp: 1.hour.ago.to_i) }
      let!(:point4) { create(:point, user: user, track: track2, timestamp: 30.minutes.ago.to_i) }

      it 'returns false for groups with less than 2 tracks' do
        result = detector.send(:merge_boundary_tracks, [track1])
        expect(result).to be false
      end

      it 'successfully merges tracks with sufficient points' do
        # Mock successful track creation
        merged_track = create(:track, user: user)
        allow(detector).to receive(:create_track_from_points).and_return(merged_track)

        result = detector.send(:merge_boundary_tracks, [track1, track2])
        expect(result).to be true
      end

      it 'collects all points from all tracks' do
        # Capture the points passed to create_track_from_points
        captured_points = nil
        allow(detector).to receive(:create_track_from_points) do |points, _distance|
          captured_points = points
          create(:track, user: user)
        end

        detector.send(:merge_boundary_tracks, [track1, track2])

        expect(captured_points).to contain_exactly(point1, point2, point3, point4)
      end

      it 'sorts points by timestamp' do
        # Create points out of order
        point_early = create(:point, user: user, track: track2, timestamp: 3.hours.ago.to_i)
        
        captured_points = nil
        allow(detector).to receive(:create_track_from_points) do |points, _distance|
          captured_points = points
          create(:track, user: user)
        end

        detector.send(:merge_boundary_tracks, [track1, track2])

        timestamps = captured_points.map(&:timestamp)
        expect(timestamps).to eq(timestamps.sort)
      end

      it 'handles insufficient points gracefully' do
        # Remove points to have less than 2 total
        Point.where(track: [track1, track2]).limit(3).destroy_all

        result = detector.send(:merge_boundary_tracks, [track1, track2])
        expect(result).to be false
      end
    end

    describe 'user settings integration' do
      it 'uses cached distance threshold' do
        # Call multiple times to test memoization
        detector.send(:distance_threshold_meters)
        detector.send(:distance_threshold_meters)

        expect(user.safe_settings).to have_received(:meters_between_routes).once
      end

      it 'uses cached time threshold' do
        # Call multiple times to test memoization
        detector.send(:time_threshold_minutes)
        detector.send(:time_threshold_minutes)

        expect(user.safe_settings).to have_received(:minutes_between_routes).once
      end
    end
  end
end
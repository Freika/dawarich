# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tracks::CreateFromPoints do
  let(:user) { create(:user) }
  let(:service) { described_class.new(user) }

  describe '#initialize' do
    it 'sets user and thresholds from user settings' do
      expect(service.user).to eq(user)
      expect(service.distance_threshold_meters).to eq(user.safe_settings.meters_between_routes.to_i)
      expect(service.time_threshold_minutes).to eq(user.safe_settings.minutes_between_routes.to_i)
    end

    context 'with custom user settings' do
      before do
        user.update!(settings: user.settings.merge({
          'meters_between_routes' => 1000,
          'minutes_between_routes' => 60
        }))
      end

      it 'uses custom settings' do
        service = described_class.new(user)
        expect(service.distance_threshold_meters).to eq(1000)
        expect(service.time_threshold_minutes).to eq(60)
      end
    end
  end

  describe '#call' do
    context 'with no points' do
      it 'returns 0 tracks created' do
        expect(service.call).to eq(0)
      end
    end

    context 'with insufficient points' do
      let!(:single_point) { create(:point, user: user, timestamp: 1.hour.ago.to_i) }

      it 'returns 0 tracks created' do
        expect(service.call).to eq(0)
      end
    end

    context 'with points that form a single track' do
      let(:base_time) { 1.hour.ago }
      let!(:points) do
        [
          create(:point, user: user, timestamp: base_time.to_i,
                lonlat: 'POINT(-74.0060 40.7128)', altitude: 10),
          create(:point, user: user, timestamp: (base_time + 5.minutes).to_i,
                lonlat: 'POINT(-74.0070 40.7130)', altitude: 15),
          create(:point, user: user, timestamp: (base_time + 10.minutes).to_i,
                lonlat: 'POINT(-74.0080 40.7132)', altitude: 20)
        ]
      end

      it 'creates one track' do
        expect { service.call }.to change(Track, :count).by(1)
      end

      it 'returns 1 track created' do
        expect(service.call).to eq(1)
      end

      it 'sets track attributes correctly' do
        service.call
        track = Track.last

        expect(track.user).to eq(user)
        expect(track.start_at).to be_within(1.second).of(base_time)
        expect(track.end_at).to be_within(1.second).of(base_time + 10.minutes)
        expect(track.duration).to eq(600) # 10 minutes in seconds
        expect(track.original_path).to be_present
        expect(track.distance).to be > 0
        expect(track.avg_speed).to be > 0
        expect(track.elevation_gain).to eq(10) # 20 - 10
        expect(track.elevation_loss).to eq(0)
        expect(track.elevation_max).to eq(20)
        expect(track.elevation_min).to eq(10)
      end

      it 'associates points with the track' do
        service.call
        track = Track.last
        expect(points.map(&:reload).map(&:track)).to all(eq(track))
      end
    end

    context 'with points that should be split by time' do
      let(:base_time) { 2.hours.ago }
      let!(:points) do
        [
          # First track
          create(:point, user: user, timestamp: base_time.to_i,
                lonlat: 'POINT(-74.0060 40.7128)'),
          create(:point, user: user, timestamp: (base_time + 5.minutes).to_i,
                lonlat: 'POINT(-74.0070 40.7130)'),

          # Gap > time threshold (default 30 minutes)
          create(:point, user: user, timestamp: (base_time + 45.minutes).to_i,
                lonlat: 'POINT(-74.0080 40.7132)'),
          create(:point, user: user, timestamp: (base_time + 50.minutes).to_i,
                lonlat: 'POINT(-74.0090 40.7134)')
        ]
      end

      it 'creates two tracks' do
        expect { service.call }.to change(Track, :count).by(2)
      end

      it 'returns 2 tracks created' do
        expect(service.call).to eq(2)
      end
    end

    context 'with points that should be split by distance' do
      let(:base_time) { 1.hour.ago }
      let!(:points) do
        [
          # First track - close points
          create(:point, user: user, timestamp: base_time.to_i,
                lonlat: 'POINT(-74.0060 40.7128)'),
          create(:point, user: user, timestamp: (base_time + 1.minute).to_i,
                lonlat: 'POINT(-74.0061 40.7129)'),

          # Far point (> distance threshold, but within time threshold)
          create(:point, user: user, timestamp: (base_time + 2.minutes).to_i,
                lonlat: 'POINT(-74.0500 40.7500)'), # ~5km away
          create(:point, user: user, timestamp: (base_time + 3.minutes).to_i,
                lonlat: 'POINT(-74.0501 40.7501)')
        ]
      end

      it 'creates two tracks' do
        expect { service.call }.to change(Track, :count).by(2)
      end
    end

    context 'with existing tracks' do
      let!(:existing_track) { create(:track, user: user) }
      let!(:points) do
        [
          create(:point, user: user, timestamp: 1.hour.ago.to_i,
                lonlat: 'POINT(-74.0060 40.7128)'),
          create(:point, user: user, timestamp: 50.minutes.ago.to_i,
                lonlat: 'POINT(-74.0070 40.7130)')
        ]
      end

      it 'destroys existing tracks and creates new ones' do
        expect { service.call }.to change(Track, :count).by(0) # -1 + 1
        expect(Track.exists?(existing_track.id)).to be false
      end
    end

    context 'with mixed elevation data' do
      let!(:points) do
        [
          create(:point, user: user, timestamp: 1.hour.ago.to_i,
                lonlat: 'POINT(-74.0060 40.7128)', altitude: 100),
          create(:point, user: user, timestamp: 50.minutes.ago.to_i,
                lonlat: 'POINT(-74.0070 40.7130)', altitude: 150),
          create(:point, user: user, timestamp: 40.minutes.ago.to_i,
                lonlat: 'POINT(-74.0080 40.7132)', altitude: 120)
        ]
      end

      it 'calculates elevation correctly' do
        service.call
        track = Track.last

        expect(track.elevation_gain).to eq(50) # 150 - 100
        expect(track.elevation_loss).to eq(30) # 150 - 120
        expect(track.elevation_max).to eq(150)
        expect(track.elevation_min).to eq(100)
      end
    end

    context 'with points missing altitude data' do
      let!(:points) do
        [
          create(:point, user: user, timestamp: 1.hour.ago.to_i,
                lonlat: 'POINT(-74.0060 40.7128)', altitude: nil),
          create(:point, user: user, timestamp: 50.minutes.ago.to_i,
                lonlat: 'POINT(-74.0070 40.7130)', altitude: nil)
        ]
      end

      it 'uses default elevation values' do
        service.call
        track = Track.last

        expect(track.elevation_gain).to eq(0)
        expect(track.elevation_loss).to eq(0)
        expect(track.elevation_max).to eq(0)
        expect(track.elevation_min).to eq(0)
      end
    end
  end

  describe 'private methods' do
    describe '#should_start_new_track?' do
      let(:point1) { build(:point, timestamp: 1.hour.ago.to_i, lonlat: 'POINT(-74.0060 40.7128)') }
      let(:point2) { build(:point, timestamp: 50.minutes.ago.to_i, lonlat: 'POINT(-74.0070 40.7130)') }

      it 'returns false when previous point is nil' do
        result = service.send(:should_start_new_track?, point1, nil)
        expect(result).to be false
      end

      it 'returns true when time threshold is exceeded' do
        # Create a point > 30 minutes later (default threshold)
        later_point = build(:point, timestamp: 29.minutes.ago.to_i, lonlat: 'POINT(-74.0070 40.7130)')

        result = service.send(:should_start_new_track?, later_point, point1)
        expect(result).to be true
      end

      it 'returns true when distance threshold is exceeded' do
        # Create a point far away (> 500m default threshold)
        far_point = build(:point, timestamp: 59.minutes.ago.to_i, lonlat: 'POINT(-74.0500 40.7500)')

        result = service.send(:should_start_new_track?, far_point, point1)
        expect(result).to be true
      end

      it 'returns false when both thresholds are not exceeded' do
        result = service.send(:should_start_new_track?, point2, point1)
        expect(result).to be false
      end
    end

    describe '#calculate_distance_kilometers' do
      let(:point1) { build(:point, lonlat: 'POINT(-74.0060 40.7128)') }
      let(:point2) { build(:point, lonlat: 'POINT(-74.0070 40.7130)') }

      it 'calculates distance between two points in kilometers' do
        distance = service.send(:calculate_distance_kilometers, point1, point2)
        expect(distance).to be > 0
        expect(distance).to be < 0.2 # Should be small distance for close points (in km)
      end
    end

    describe '#calculate_average_speed' do
      it 'calculates speed correctly' do
        # 1000 meters in 100 seconds = 10 m/s = 36 km/h
        speed = service.send(:calculate_average_speed, 1000, 100)
        expect(speed).to eq(36.0)
      end

      it 'returns 0 for zero duration' do
        speed = service.send(:calculate_average_speed, 1000, 0)
        expect(speed).to eq(0.0)
      end

      it 'returns 0 for zero distance' do
        speed = service.send(:calculate_average_speed, 0, 100)
        expect(speed).to eq(0.0)
      end
    end

    describe '#calculate_track_distance' do
      let(:points) do
        [
          build(:point, lonlat: 'POINT(-74.0060 40.7128)'),
          build(:point, lonlat: 'POINT(-74.0070 40.7130)')
        ]
      end

      before do
        allow(Point).to receive(:total_distance).and_return(1.5) # 1.5 km
      end

      it 'converts km to meters by default' do
        distance = service.send(:calculate_track_distance, points)
        expect(distance).to eq(1500) # 1.5 km = 1500 meters
      end

      context 'with miles unit' do
        before do
          user.update!(settings: user.settings.merge({'maps' => {'distance_unit' => 'miles'}}))
        end

        it 'converts miles to meters' do
          distance = service.send(:calculate_track_distance, points)
          expect(distance).to eq(2414) # 1.5 miles ≈ 2414 meters (rounded)
        end
      end
    end
  end
end

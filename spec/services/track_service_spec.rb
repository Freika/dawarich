require 'rails_helper'

RSpec.describe TrackService, type: :service do
  let(:user) { create(:user) }
  let(:service) { described_class.new(user, **options) }
  let(:options) { {} }

  describe '#initialize' do
    it 'sets default values' do
      expect(service.user).to eq(user)
      expect(service.mode).to eq(:bulk)
      expect(service.cleanup_tracks).to eq(false)
      expect(service.time_threshold_minutes).to eq(60)
      expect(service.distance_threshold_meters).to eq(500)
    end

    context 'with custom options' do
      let(:options) do
        {
          mode: :incremental,
          cleanup_tracks: true,
          time_threshold_minutes: 30,
          distance_threshold_meters: 1000
        }
      end

      it 'uses provided options' do
        expect(service.mode).to eq(:incremental)
        expect(service.cleanup_tracks).to eq(true)
        expect(service.time_threshold_minutes).to eq(30)
        expect(service.distance_threshold_meters).to eq(1000)
      end
    end
  end

  describe '#call' do
    context 'with no points' do
      it 'returns 0' do
        result = service.call
        expect(result).to eq(0)
      end
    end

    context 'with points' do
      let!(:points) do
        [
          create(:point, user: user, timestamp: 1.hour.ago.to_i, lonlat: 'POINT(13.404954 52.520008)'),
          create(:point, user: user, timestamp: 30.minutes.ago.to_i, lonlat: 'POINT(13.405954 52.521008)'),
          create(:point, user: user, timestamp: Time.current.to_i, lonlat: 'POINT(13.406954 52.522008)')
        ]
      end

      it 'creates tracks from points' do
        expect { service.call }.to change(Track, :count).by(1)
      end

      it 'assigns points to created tracks' do
        service.call
        track = Track.last
        expect(points.map(&:reload).map(&:track)).to all(eq(track))
      end

      it 'returns count of tracks created' do
        result = service.call
        expect(result).to eq(1)
      end
    end

    context 'with cleanup_tracks enabled' do
      let(:options) { { cleanup_tracks: true } }
      let!(:existing_track) { create(:track, user: user) }

      it 'removes existing tracks in bulk mode' do
        expect { service.call }.to change(Track, :count).by(-1)
      end
    end

    context 'with incremental mode and old point' do
      let(:options) { { mode: :incremental, point_id: point.id } }
      let!(:point) { create(:point, user: user, created_at: 2.hours.ago) }

      it 'returns early for old points' do
        result = service.call
        expect(result).to eq(0)
      end
    end
  end

  describe '#load_points' do
    context 'in bulk mode' do
      let(:service) { described_class.new(user, mode: :bulk) }
      let!(:assigned_point) { create(:point, user: user, track: create(:track, user: user)) }
      let!(:unassigned_point) { create(:point, user: user) }

      it 'loads only unassigned points' do
        points = service.send(:load_points)
        expect(points).to contain_exactly(unassigned_point)
      end
    end

    context 'in incremental mode' do
      let(:service) { described_class.new(user, mode: :incremental) }
      let!(:old_point) { create(:point, user: user, timestamp: 3.hours.ago.to_i) }
      let!(:recent_unassigned_point) { create(:point, user: user, timestamp: 1.hour.ago.to_i) }
      let!(:active_track_point) { create(:point, user: user, track: recent_track, timestamp: 1.hour.ago.to_i) }
      let(:recent_track) { create(:track, user: user, end_at: 1.hour.ago) }

      it 'loads recent unassigned points and active track points' do
        points = service.send(:load_points)
        expect(points).to contain_exactly(recent_unassigned_point, active_track_point)
      end
    end
  end

  describe '#segment_points' do
    let(:service) { described_class.new(user) }

    context 'with points that should be segmented' do
      let(:points) do
        [
          create(:point, user: user, timestamp: 2.hours.ago.to_i, lonlat: 'POINT(13.404954 52.520008)'),
          create(:point, user: user, timestamp: 1.hour.ago.to_i, lonlat: 'POINT(13.405954 52.521008)'),
          create(:point, user: user, timestamp: Time.current.to_i, lonlat: 'POINT(13.406954 52.522008)')
        ]
      end

      it 'creates segments based on time threshold' do
        segments = service.send(:segment_points, points)
        expect(segments.count).to eq(2) # Should split due to time gap
      end
    end

    context 'with points that should stay together' do
      let(:points) do
        [
          create(:point, user: user, timestamp: 30.minutes.ago.to_i, lonlat: 'POINT(13.404954 52.520008)'),
          create(:point, user: user, timestamp: 20.minutes.ago.to_i, lonlat: 'POINT(13.405954 52.521008)'),
          create(:point, user: user, timestamp: 10.minutes.ago.to_i, lonlat: 'POINT(13.406954 52.522008)')
        ]
      end

      it 'keeps points in single segment' do
        segments = service.send(:segment_points, points)
        expect(segments.count).to eq(1)
        expect(segments.first.count).to eq(3)
      end
    end
  end

  describe '#should_start_new_segment?' do
    let(:service) { described_class.new(user) }
    let(:previous_point) { create(:point, user: user, timestamp: 2.hours.ago.to_i, lonlat: 'POINT(13.404954 52.520008)') }

    context 'with no previous point' do
      it 'returns false' do
        current_point = create(:point, user: user, timestamp: 1.hour.ago.to_i)
        result = service.send(:should_start_new_segment?, current_point, nil)
        expect(result).to eq(false)
      end
    end

    context 'with time threshold exceeded' do
      it 'returns true' do
        current_point = create(:point, user: user, timestamp: Time.current.to_i)
        result = service.send(:should_start_new_segment?, current_point, previous_point)
        expect(result).to eq(true)
      end
    end

    context 'with distance threshold exceeded' do
      it 'returns true' do
        # Create a point very far away (should exceed 500m default threshold)
        current_point = create(:point, user: user, timestamp: 1.hour.ago.to_i, lonlat: 'POINT(14.404954 53.520008)')
        result = service.send(:should_start_new_segment?, current_point, previous_point)
        expect(result).to eq(true)
      end
    end

    context 'with neither threshold exceeded' do
      it 'returns false' do
        # Create a point nearby and within time threshold
        current_point = create(:point, user: user, timestamp: 1.hour.ago.to_i, lonlat: 'POINT(13.405954 52.521008)')
        result = service.send(:should_start_new_segment?, current_point, previous_point)
        expect(result).to eq(false)
      end
    end
  end

  describe '#create_track_from_points' do
    let(:service) { described_class.new(user) }
    let(:points) do
      [
        create(:point, user: user, timestamp: 1.hour.ago.to_i, lonlat: 'POINT(13.404954 52.520008)', altitude: 100),
        create(:point, user: user, timestamp: 30.minutes.ago.to_i, lonlat: 'POINT(13.405954 52.521008)', altitude: 120),
        create(:point, user: user, timestamp: Time.current.to_i, lonlat: 'POINT(13.406954 52.522008)', altitude: 110)
      ]
    end

    it 'creates a track with correct attributes' do
      track = service.send(:create_track_from_points, points)
      
      expect(track).to be_persisted
      expect(track.user).to eq(user)
      expect(track.start_at).to be_within(1.second).of(Time.zone.at(points.first.timestamp))
      expect(track.end_at).to be_within(1.second).of(Time.zone.at(points.last.timestamp))
      expect(track.distance).to be > 0
      expect(track.duration).to be > 0
      expect(track.avg_speed).to be >= 0
      expect(track.elevation_gain).to be >= 0
      expect(track.elevation_loss).to be >= 0
    end

    it 'assigns points to the track' do
      track = service.send(:create_track_from_points, points)
      expect(points.map(&:reload).map(&:track)).to all(eq(track))
    end

    context 'with insufficient points' do
      let(:points) { [create(:point, user: user)] }

      it 'returns nil' do
        result = service.send(:create_track_from_points, points)
        expect(result).to be_nil
      end
    end
  end

  describe '#calculate_distance' do
    let(:service) { described_class.new(user) }
    let(:points) do
      [
        create(:point, user: user, lonlat: 'POINT(13.404954 52.520008)'),
        create(:point, user: user, lonlat: 'POINT(13.405954 52.521008)')
      ]
    end

    it 'calculates distance between points' do
      distance = service.send(:calculate_distance, points)
      expect(distance).to be > 0
      expect(distance).to be_a(Integer) # Should be rounded to integer
    end
  end

  describe '#calculate_average_speed' do
    let(:service) { described_class.new(user) }
    let(:points) do
      [
        create(:point, user: user, timestamp: 1.hour.ago.to_i),
        create(:point, user: user, timestamp: Time.current.to_i)
      ]
    end

    it 'calculates average speed' do
      speed = service.send(:calculate_average_speed, points)
      expect(speed).to be >= 0
      expect(speed).to be_a(Float)
    end

    context 'with zero duration' do
      let(:points) do
        timestamp = Time.current.to_i
        [
          create(:point, user: user, timestamp: timestamp),
          create(:point, user: user, timestamp: timestamp)
        ]
      end

      it 'returns 0' do
        speed = service.send(:calculate_average_speed, points)
        expect(speed).to eq(0.0)
      end
    end
  end

  describe '#calculate_elevation_gain' do
    let(:service) { described_class.new(user) }

    context 'with ascending points' do
      let(:points) do
        [
          create(:point, user: user, altitude: 100),
          create(:point, user: user, altitude: 120),
          create(:point, user: user, altitude: 110)
        ]
      end

      it 'calculates elevation gain' do
        gain = service.send(:calculate_elevation_gain, points)
        expect(gain).to eq(20) # 100 -> 120 = +20
      end
    end

    context 'with no altitude data' do
      let(:points) do
        [
          create(:point, user: user, altitude: nil),
          create(:point, user: user, altitude: nil)
        ]
      end

      it 'returns 0' do
        gain = service.send(:calculate_elevation_gain, points)
        expect(gain).to eq(0)
      end
    end
  end

  describe '#calculate_elevation_loss' do
    let(:service) { described_class.new(user) }

    context 'with descending points' do
      let(:points) do
        [
          create(:point, user: user, altitude: 120),
          create(:point, user: user, altitude: 100),
          create(:point, user: user, altitude: 110)
        ]
      end

      it 'calculates elevation loss' do
        loss = service.send(:calculate_elevation_loss, points)
        expect(loss).to eq(20) # 120 -> 100 = -20 (loss)
      end
    end
  end
end
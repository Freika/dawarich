# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tracks::TrackBuilder do
  # Create a test class that includes the concern for testing
  let(:test_class) do
    Class.new do
      include Tracks::TrackBuilder

      def initialize(user)
        @user = user
      end

      private

      attr_reader :user
    end
  end

  let(:user) { create(:user) }
  let(:builder) { test_class.new(user) }

  before do
    # Set up user settings for consistent testing
    allow_any_instance_of(Users::SafeSettings).to receive(:distance_unit).and_return('km')
  end

  describe '#create_track_from_points' do
    context 'with valid points' do
      let!(:points) do
        [
          create(:point, user: user, lonlat: 'POINT(-74.0060 40.7128)',
                 timestamp: 2.hours.ago.to_i, altitude: 100),
          create(:point, user: user, lonlat: 'POINT(-74.0070 40.7130)',
                 timestamp: 1.hour.ago.to_i, altitude: 110),
          create(:point, user: user, lonlat: 'POINT(-74.0080 40.7132)',
                 timestamp: 30.minutes.ago.to_i, altitude: 105)
        ]
      end

      it 'creates a track with correct attributes' do
        track = builder.create_track_from_points(points)

        expect(track).to be_persisted
        expect(track.user).to eq(user)
        expect(track.start_at).to be_within(1.second).of(Time.zone.at(points.first.timestamp))
        expect(track.end_at).to be_within(1.second).of(Time.zone.at(points.last.timestamp))
        expect(track.distance).to be > 0
        expect(track.duration).to eq(90.minutes.to_i)
        expect(track.avg_speed).to be > 0
        expect(track.original_path).to be_present
      end

      it 'calculates elevation statistics correctly' do
        track = builder.create_track_from_points(points)

        expect(track.elevation_gain).to eq(10) # 110 - 100
        expect(track.elevation_loss).to eq(5)  # 110 - 105
        expect(track.elevation_max).to eq(110)
        expect(track.elevation_min).to eq(100)
      end

      it 'associates points with the track' do
        track = builder.create_track_from_points(points)

        points.each(&:reload)
        expect(points.map(&:track)).to all(eq(track))
      end
    end

    context 'with insufficient points' do
      let(:single_point) { [create(:point, user: user)] }

      it 'returns nil for single point' do
        result = builder.create_track_from_points(single_point)
        expect(result).to be_nil
      end

      it 'returns nil for empty array' do
        result = builder.create_track_from_points([])
        expect(result).to be_nil
      end
    end

    context 'when track save fails' do
      let(:points) do
        [
          create(:point, user: user, timestamp: 1.hour.ago.to_i),
          create(:point, user: user, timestamp: 30.minutes.ago.to_i)
        ]
      end

      before do
        allow_any_instance_of(Track).to receive(:save).and_return(false)
      end

      it 'returns nil and logs error' do
        expect(Rails.logger).to receive(:error).with(
          /Failed to create track for user #{user.id}/
        )

        result = builder.create_track_from_points(points)
        expect(result).to be_nil
      end
    end
  end

  describe '#build_path' do
    let(:points) do
      [
        create(:point, lonlat: 'POINT(-74.0060 40.7128)'),
        create(:point, lonlat: 'POINT(-74.0070 40.7130)')
      ]
    end

    it 'builds path using Tracks::BuildPath service' do
      expect(Tracks::BuildPath).to receive(:new).with(
        points
      ).and_call_original

      result = builder.build_path(points)
      expect(result).to respond_to(:as_text)
    end
  end

  describe '#calculate_track_distance' do
    let(:points) do
      [
        create(:point, user: user, lonlat: 'POINT(-74.0060 40.7128)'),
        create(:point, user: user, lonlat: 'POINT(-74.0070 40.7130)')
      ]
    end

    before do
      # Mock Point.total_distance to return distance in meters
      allow(Point).to receive(:total_distance).and_return(1500) # 1500 meters
    end

    it 'stores distance in meters regardless of user unit preference' do
      result = builder.calculate_track_distance(points)
      expect(result).to eq(1500) # Always stored as meters
    end

    it 'rounds distance to nearest meter' do
      allow(Point).to receive(:total_distance).and_return(1500.7)
      result = builder.calculate_track_distance(points)
      expect(result).to eq(1501) # Rounded to nearest meter
    end
  end

  describe '#calculate_duration' do
    let(:start_time) { 2.hours.ago.to_i }
    let(:end_time) { 1.hour.ago.to_i }
    let(:points) do
      [
        double(timestamp: start_time),
        double(timestamp: end_time)
      ]
    end

    it 'calculates duration in seconds' do
      result = builder.calculate_duration(points)
      expect(result).to eq(1.hour.to_i)
    end
  end

  describe '#calculate_average_speed' do
    context 'with valid distance and duration' do
      it 'calculates speed in km/h' do
        distance_meters = 1000  # 1 km
        duration_seconds = 3600 # 1 hour

        result = builder.calculate_average_speed(distance_meters, duration_seconds)
        expect(result).to eq(1.0) # 1 km/h
      end

      it 'rounds to 2 decimal places' do
        distance_meters = 1500  # 1.5 km
        duration_seconds = 1800 # 30 minutes

        result = builder.calculate_average_speed(distance_meters, duration_seconds)
        expect(result).to eq(3.0) # 3 km/h
      end
    end

    context 'with invalid inputs' do
      it 'returns 0.0 for zero duration' do
        result = builder.calculate_average_speed(1000, 0)
        expect(result).to eq(0.0)
      end

      it 'returns 0.0 for zero distance' do
        result = builder.calculate_average_speed(0, 3600)
        expect(result).to eq(0.0)
      end

      it 'returns 0.0 for negative duration' do
        result = builder.calculate_average_speed(1000, -3600)
        expect(result).to eq(0.0)
      end
    end
  end

  describe '#calculate_elevation_stats' do
    context 'with elevation data' do
      let(:points) do
        [
          double(altitude: 100),
          double(altitude: 150),
          double(altitude: 120),
          double(altitude: 180),
          double(altitude: 160)
        ]
      end

      it 'calculates elevation gain correctly' do
        result = builder.calculate_elevation_stats(points)
        expect(result[:gain]).to eq(110) # (150-100) + (180-120) = 50 + 60 = 110
      end

      it 'calculates elevation loss correctly' do
        result = builder.calculate_elevation_stats(points)
        expect(result[:loss]).to eq(50) # (150-120) + (180-160) = 30 + 20 = 50
      end

      it 'finds max elevation' do
        result = builder.calculate_elevation_stats(points)
        expect(result[:max]).to eq(180)
      end

      it 'finds min elevation' do
        result = builder.calculate_elevation_stats(points)
        expect(result[:min]).to eq(100)
      end
    end

    context 'with no elevation data' do
      let(:points) do
        [
          double(altitude: nil),
          double(altitude: nil)
        ]
      end

      it 'returns default elevation stats' do
        result = builder.calculate_elevation_stats(points)
        expect(result).to eq({
          gain: 0,
          loss: 0,
          max: 0,
          min: 0
        })
      end
    end

    context 'with mixed elevation data' do
      let(:points) do
        [
          double(altitude: 100),
          double(altitude: nil),
          double(altitude: 150)
        ]
      end

      it 'ignores nil values' do
        result = builder.calculate_elevation_stats(points)
        expect(result[:gain]).to eq(50) # 150 - 100
        expect(result[:loss]).to eq(0)
        expect(result[:max]).to eq(150)
        expect(result[:min]).to eq(100)
      end
    end
  end

  describe '#default_elevation_stats' do
    it 'returns hash with zero values' do
      result = builder.default_elevation_stats
      expect(result).to eq({
        gain: 0,
        loss: 0,
        max: 0,
        min: 0
      })
    end
  end

  describe 'user method requirement' do
    let(:invalid_class) do
      Class.new do
        include Tracks::TrackBuilder
        # Does not implement user method
      end
    end

    it 'raises NotImplementedError when user method is not implemented' do
      invalid_builder = invalid_class.new
      expect { invalid_builder.send(:user) }.to raise_error(
        NotImplementedError,
        "Including class must implement user method"
      )
    end
  end

  describe 'integration test' do
    let!(:points) do
      [
        create(:point, user: user, lonlat: 'POINT(-74.0060 40.7128)',
               timestamp: 2.hours.ago.to_i, altitude: 100),
        create(:point, user: user, lonlat: 'POINT(-74.0070 40.7130)',
               timestamp: 1.hour.ago.to_i, altitude: 120)
      ]
    end

    it 'creates a complete track end-to-end' do
      expect { builder.create_track_from_points(points) }.to change(Track, :count).by(1)

      track = Track.last
      expect(track.user).to eq(user)
      expect(track.points).to match_array(points)
      expect(track.distance).to be > 0
      expect(track.duration).to eq(1.hour.to_i)
      expect(track.elevation_gain).to eq(20)
    end
  end
end

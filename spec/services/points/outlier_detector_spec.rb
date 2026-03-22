# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::OutlierDetector do
  let(:user) { create(:user) }
  let(:base_time) { DateTime.new(2024, 5, 1, 12, 0, 0).to_i }

  # Helper: create a point at a given lat/lon and time offset (seconds)
  def create_point_at(lat:, lon:, time_offset: 0, outlier: false)
    create(:point,
      user: user,
      latitude: lat,
      longitude: lon,
      lonlat: "POINT(#{lon} #{lat})",
      timestamp: base_time + time_offset,
      outlier: outlier
    )
  end

  describe '#call' do
    context 'with normal movement' do
      before do
        # ~1 km apart, 10 minutes between each = ~6 km/h (walking)
        create_point_at(lat: 51.5000, lon: -0.1200, time_offset: 0)
        create_point_at(lat: 51.5090, lon: -0.1200, time_offset: 600)
        create_point_at(lat: 51.5180, lon: -0.1200, time_offset: 1200)
      end

      it 'flags no points' do
        result = described_class.new(user).call
        expect(result).to eq(0)
        expect(user.points.where(outlier: true).count).to eq(0)
      end
    end

    context 'with a single teleport spike' do
      before do
        # Point 1: London
        create_point_at(lat: 51.5074, lon: -0.1278, time_offset: 0)
        # Point 2: Tokyo (teleport!) — 1 minute later
        create_point_at(lat: 35.6762, lon: 139.6503, time_offset: 60)
        # Point 3: London again — 1 minute after that
        create_point_at(lat: 51.5080, lon: -0.1280, time_offset: 120)
      end

      it 'flags the teleported point' do
        result = described_class.new(user).call
        expect(result).to eq(1)

        outliers = user.points.where(outlier: true)
        expect(outliers.count).to eq(1)
        # The Tokyo point should be the outlier
        expect(outliers.first.lat).to be_within(0.01).of(35.6762)
      end
    end

    context 'with a large time gap' do
      before do
        # Point 1: London
        create_point_at(lat: 51.5074, lon: -0.1278, time_offset: 0)
        # Point 2: New York — 10 hours later (plausible flight)
        create_point_at(lat: 40.7128, lon: -74.0060, time_offset: 36_000)
      end

      it 'does not flag points separated by more than 1 hour' do
        result = described_class.new(user).call
        expect(result).to eq(0)
        expect(user.points.where(outlier: true).count).to eq(0)
      end
    end

    context 'with flight-speed movement below threshold' do
      before do
        # London to Paris, ~340km, in 50 minutes = ~408 km/h (fast train or slow plane)
        create_point_at(lat: 51.5074, lon: -0.1278, time_offset: 0)
        create_point_at(lat: 48.8566, lon: 2.3522, time_offset: 3000)
      end

      it 'does not flag points within speed threshold' do
        result = described_class.new(user).call
        expect(result).to eq(0)
      end
    end

    context 'with custom speed threshold' do
      before do
        user.settings['max_speed_kmh'] = 100
        user.save!

        # London to Paris, ~340km, in 50 minutes = ~408 km/h
        create_point_at(lat: 51.5074, lon: -0.1278, time_offset: 0)
        create_point_at(lat: 48.8566, lon: 2.3522, time_offset: 3000)
        # Back near London
        create_point_at(lat: 51.5080, lon: -0.1280, time_offset: 6000)
      end

      it 'uses the user configured threshold' do
        result = described_class.new(user).call
        expect(result).to eq(1)
      end
    end

    context 'with date range filter' do
      before do
        # Points on day 1 — normal
        create_point_at(lat: 51.5000, lon: -0.1200, time_offset: 0)
        create_point_at(lat: 51.5090, lon: -0.1200, time_offset: 600)

        # Points on day 2 — has outlier
        create_point_at(lat: 51.5074, lon: -0.1278, time_offset: 86_400)
        create_point_at(lat: 35.6762, lon: 139.6503, time_offset: 86_460) # Tokyo spike
        create_point_at(lat: 51.5080, lon: -0.1280, time_offset: 86_520)
      end

      it 'only processes points in the given range' do
        day2_start = Time.zone.at(base_time + 86_400)
        day2_end = Time.zone.at(base_time + 86_400 + 86_399)

        result = described_class.new(user, start_at: day2_start, end_at: day2_end).call
        expect(result).to eq(1)
      end
    end

    context 'with already flagged outliers' do
      before do
        create_point_at(lat: 51.5074, lon: -0.1278, time_offset: 0)
        create_point_at(lat: 35.6762, lon: 139.6503, time_offset: 60, outlier: true)
        create_point_at(lat: 51.5080, lon: -0.1280, time_offset: 120)
      end

      it 'does not double-count previously flagged outliers' do
        result = described_class.new(user).call
        expect(result).to eq(0)
        expect(user.points.where(outlier: true).count).to eq(1)
      end
    end

    context 'with a trailing spike (no third point for sandwich)' do
      before do
        # Point 1: London
        create_point_at(lat: 51.5074, lon: -0.1278, time_offset: 0)
        # Point 2: Tokyo (teleport!) — 1 minute later, no third point
        create_point_at(lat: 35.6762, lon: 139.6503, time_offset: 60)
      end

      it 'flags the outlier even without a third point' do
        result = described_class.new(user).call
        expect(result).to eq(1)

        outliers = user.points.where(outlier: true)
        expect(outliers.count).to eq(1)
        expect(outliers.first.lat).to be_within(0.01).of(35.6762)
      end
    end
  end
end

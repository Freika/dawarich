# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tracks::IncrementalProcessor do
  let(:user) { create(:user) }
  let(:safe_settings) { user.safe_settings }

  before do
    allow(user).to receive(:safe_settings).and_return(safe_settings)
    allow(safe_settings).to receive(:minutes_between_routes).and_return(30)
    allow(safe_settings).to receive(:meters_between_routes).and_return(500)
  end

  describe '#call' do
    context 'with imported points' do
      let(:imported_point) { create(:point, user: user, import: create(:import)) }
      let(:processor) { described_class.new(user, imported_point) }

      it 'does not process imported points' do
        expect(Tracks::CreateJob).not_to receive(:perform_later)

        processor.call
      end
    end

    context 'with first point for user' do
      let(:new_point) { create(:point, user: user) }
      let(:processor) { described_class.new(user, new_point) }

      it 'processes first point' do
        expect(Tracks::CreateJob).to receive(:perform_later)
          .with(user.id, start_at: nil, end_at: nil, mode: :none)
        processor.call
      end
    end

    context 'with thresholds exceeded' do
      let(:previous_point) { create(:point, user: user, timestamp: 1.hour.ago.to_i) }
      let(:new_point) { create(:point, user: user, timestamp: Time.current.to_i) }
      let(:processor) { described_class.new(user, new_point) }

      before do
        # Create previous point first
        previous_point
      end

      it 'processes when time threshold exceeded' do
        expect(Tracks::CreateJob).to receive(:perform_later)
          .with(user.id, start_at: nil, end_at: Time.at(previous_point.timestamp), mode: :none)
        processor.call
      end
    end

    context 'with existing tracks' do
      let(:existing_track) { create(:track, user: user, end_at: 2.hours.ago) }
      let(:previous_point) { create(:point, user: user, timestamp: 1.hour.ago.to_i) }
      let(:new_point) { create(:point, user: user, timestamp: Time.current.to_i) }
      let(:processor) { described_class.new(user, new_point) }

      before do
        existing_track
        previous_point
      end

      it 'uses existing track end time as start_at' do
        expect(Tracks::CreateJob).to receive(:perform_later)
          .with(user.id, start_at: existing_track.end_at, end_at: Time.at(previous_point.timestamp), mode: :none)
        processor.call
      end
    end

    context 'with distance threshold exceeded' do
      let(:previous_point) do
        create(:point, user: user, timestamp: 10.minutes.ago.to_i, lonlat: 'POINT(0 0)')
      end
      let(:new_point) do
        create(:point, user: user, timestamp: Time.current.to_i, lonlat: 'POINT(1 1)')
      end
      let(:processor) { described_class.new(user, new_point) }

      before do
        # Create previous point first
        previous_point
        # Mock distance calculation to exceed threshold
        allow_any_instance_of(Point).to receive(:distance_to).and_return(1.0) # 1 km = 1000m
      end

      it 'processes when distance threshold exceeded' do
        expect(Tracks::CreateJob).to receive(:perform_later)
          .with(user.id, start_at: nil, end_at: Time.at(previous_point.timestamp), mode: :none)
        processor.call
      end
    end

    context 'with thresholds not exceeded' do
      let(:previous_point) { create(:point, user: user, timestamp: 10.minutes.ago.to_i) }
      let(:new_point) { create(:point, user: user, timestamp: Time.current.to_i) }
      let(:processor) { described_class.new(user, new_point) }

      before do
        # Create previous point first
        previous_point
        # Mock distance to be within threshold
        allow_any_instance_of(Point).to receive(:distance_to).and_return(0.1) # 100m
      end

      it 'does not process when thresholds not exceeded' do
        expect(Tracks::CreateJob).not_to receive(:perform_later)
        processor.call
      end
    end
  end

  describe '#should_process?' do
    let(:processor) { described_class.new(user, new_point) }

    context 'with imported point' do
      let(:new_point) { create(:point, user: user, import: create(:import)) }

      it 'returns false' do
        expect(processor.send(:should_process?)).to be false
      end
    end

    context 'with first point for user' do
      let(:new_point) { create(:point, user: user) }

      it 'returns true' do
        expect(processor.send(:should_process?)).to be true
      end
    end

    context 'with thresholds exceeded' do
      let(:previous_point) { create(:point, user: user, timestamp: 1.hour.ago.to_i) }
      let(:new_point) { create(:point, user: user, timestamp: Time.current.to_i) }

      before do
        previous_point # Create previous point
      end

      it 'returns true when time threshold exceeded' do
        expect(processor.send(:should_process?)).to be true
      end
    end

    context 'with thresholds not exceeded' do
      let(:previous_point) { create(:point, user: user, timestamp: 10.minutes.ago.to_i) }
      let(:new_point) { create(:point, user: user, timestamp: Time.current.to_i) }

      before do
        previous_point # Create previous point
        allow_any_instance_of(Point).to receive(:distance_to).and_return(0.1) # 100m
      end

      it 'returns false when thresholds not exceeded' do
        expect(processor.send(:should_process?)).to be false
      end
    end
  end

  describe '#exceeds_thresholds?' do
    let(:processor) { described_class.new(user, new_point) }
    let(:previous_point) { create(:point, user: user, timestamp: 1.hour.ago.to_i) }
    let(:new_point) { create(:point, user: user, timestamp: Time.current.to_i) }

    context 'with time threshold exceeded' do
      before do
        allow(safe_settings).to receive(:minutes_between_routes).and_return(30)
      end

      it 'returns true' do
        result = processor.send(:exceeds_thresholds?, previous_point, new_point)
        expect(result).to be true
      end
    end

    context 'with distance threshold exceeded' do
      before do
        allow(safe_settings).to receive(:minutes_between_routes).and_return(120) # 2 hours
        allow(safe_settings).to receive(:meters_between_routes).and_return(400)
        allow_any_instance_of(Point).to receive(:distance_to).and_return(0.5) # 500m
      end

      it 'returns true' do
        result = processor.send(:exceeds_thresholds?, previous_point, new_point)
        expect(result).to be true
      end
    end

    context 'with neither threshold exceeded' do
      before do
        allow(safe_settings).to receive(:minutes_between_routes).and_return(120) # 2 hours
        allow(safe_settings).to receive(:meters_between_routes).and_return(600)
        allow_any_instance_of(Point).to receive(:distance_to).and_return(0.1) # 100m
      end

      it 'returns false' do
        result = processor.send(:exceeds_thresholds?, previous_point, new_point)
        expect(result).to be false
      end
    end
  end

  describe '#time_difference_minutes' do
    let(:processor) { described_class.new(user, new_point) }
    let(:point1) { create(:point, user: user, timestamp: 1.hour.ago.to_i) }
    let(:point2) { create(:point, user: user, timestamp: Time.current.to_i) }
    let(:new_point) { point2 }

    it 'calculates time difference in minutes' do
      result = processor.send(:time_difference_minutes, point1, point2)
      expect(result).to be_within(1).of(60) # Approximately 60 minutes
    end
  end

  describe '#distance_difference_meters' do
    let(:processor) { described_class.new(user, new_point) }
    let(:point1) { create(:point, user: user) }
    let(:point2) { create(:point, user: user) }
    let(:new_point) { point2 }

    before do
      allow(point1).to receive(:distance_to).with(point2).and_return(1.5) # 1.5 km
    end

    it 'calculates distance difference in meters' do
      result = processor.send(:distance_difference_meters, point1, point2)
      expect(result).to eq(1500) # 1.5 km = 1500 m
    end
  end

  describe 'threshold configuration' do
    let(:processor) { described_class.new(user, create(:point, user: user)) }

    before do
      allow(safe_settings).to receive(:minutes_between_routes).and_return(45)
      allow(safe_settings).to receive(:meters_between_routes).and_return(750)
    end

    it 'uses configured time threshold' do
      expect(processor.send(:time_threshold_minutes)).to eq(45)
    end

    it 'uses configured distance threshold' do
      expect(processor.send(:distance_threshold_meters)).to eq(750)
    end
  end
end

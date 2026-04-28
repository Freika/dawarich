# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::AnomalyFilter do
  let(:user) { create(:user) }
  let(:start_time) { 1.hour.ago.to_i }
  let(:end_time) { Time.current.to_i }

  describe '#call' do
    context 'Pass 1: accuracy filter' do
      # Use nearby coordinates so Pass 2 speed filter does not interfere
      let(:base_lat) { 52.52 }
      let(:base_lon) { 13.405 }

      let!(:good_point) do
        create(:point, user: user, accuracy: 15, timestamp: 30.minutes.ago.to_i,
               latitude: base_lat, longitude: base_lon,
               lonlat: "POINT(#{base_lon} #{base_lat})")
      end
      let!(:bad_accuracy) do
        create(:point, user: user, accuracy: 500, timestamp: 29.minutes.ago.to_i,
               latitude: base_lat + 0.0001, longitude: base_lon + 0.0001,
               lonlat: "POINT(#{base_lon + 0.0001} #{base_lat + 0.0001})")
      end
      let!(:no_accuracy) do
        create(:point, user: user, accuracy: nil, timestamp: 28.minutes.ago.to_i,
               latitude: base_lat + 0.0002, longitude: base_lon + 0.0002,
               lonlat: "POINT(#{base_lon + 0.0002} #{base_lat + 0.0002})")
      end
      let!(:borderline) do
        create(:point, user: user, accuracy: 100, timestamp: 27.minutes.ago.to_i,
               latitude: base_lat + 0.0003, longitude: base_lon + 0.0003,
               lonlat: "POINT(#{base_lon + 0.0003} #{base_lat + 0.0003})")
      end
      let!(:just_over) do
        create(:point, user: user, accuracy: 101, timestamp: 26.minutes.ago.to_i,
               latitude: base_lat + 0.0004, longitude: base_lon + 0.0004,
               lonlat: "POINT(#{base_lon + 0.0004} #{base_lat + 0.0004})")
      end

      before { described_class.new(user.id, start_time, end_time).call }

      it 'marks points with accuracy > 100 as anomaly' do
        expect(bad_accuracy.reload.anomaly).to be true
        expect(just_over.reload.anomaly).to be true
      end

      it 'does not mark points with accuracy <= 100' do
        expect(good_point.reload.anomaly).not_to be true
        expect(borderline.reload.anomaly).not_to be true
      end

      it 'does not mark points with nil accuracy' do
        expect(no_accuracy.reload.anomaly).not_to be true
      end
    end

    context 'Pass 2: speed-based sandwich test' do
      let(:base_time) { 30.minutes.ago.to_i }
      let(:base_lat) { 52.52 }
      let(:base_lon) { 13.405 }

      # Normal walking points ~10m apart, 60s intervals
      let!(:p1) do
        create(:point, user: user, latitude: base_lat, longitude: base_lon,
               lonlat: "POINT(#{base_lon} #{base_lat})",
               timestamp: base_time, accuracy: 10)
      end
      let!(:p2) do
        create(:point, user: user, latitude: base_lat + 0.0001, longitude: base_lon + 0.0001,
               lonlat: "POINT(#{base_lon + 0.0001} #{base_lat + 0.0001})",
               timestamp: base_time + 60, accuracy: 10)
      end
      # Teleportation spike: 10 degrees away (>1000km) but only 60 seconds later
      let!(:spike) do
        create(:point, user: user, latitude: base_lat + 10.0, longitude: base_lon + 10.0,
               lonlat: "POINT(#{base_lon + 10.0} #{base_lat + 10.0})",
               timestamp: base_time + 120, accuracy: 10)
      end
      let!(:p4) do
        create(:point, user: user, latitude: base_lat + 0.0002, longitude: base_lon + 0.0002,
               lonlat: "POINT(#{base_lon + 0.0002} #{base_lat + 0.0002})",
               timestamp: base_time + 180, accuracy: 10)
      end
      let!(:p5) do
        create(:point, user: user, latitude: base_lat + 0.0003, longitude: base_lon + 0.0003,
               lonlat: "POINT(#{base_lon + 0.0003} #{base_lat + 0.0003})",
               timestamp: base_time + 240, accuracy: 10)
      end

      before { described_class.new(user.id, start_time, end_time).call }

      it 'marks the teleportation spike as anomaly' do
        expect(spike.reload.anomaly).to be true
      end

      it 'does not mark normal points as anomaly' do
        expect(p1.reload.anomaly).not_to be true
        expect(p2.reload.anomaly).not_to be true
        expect(p4.reload.anomaly).not_to be true
        expect(p5.reload.anomaly).not_to be true
      end
    end

    context 'Pass 2: same-timestamp points' do
      let!(:p1) do
        create(:point, user: user, latitude: 52.52, longitude: 13.405,
               lonlat: 'POINT(13.405 52.52)', timestamp: 30.minutes.ago.to_i)
      end
      let!(:p2) do
        create(:point, user: user, latitude: 52.521, longitude: 13.406,
               lonlat: 'POINT(13.406 52.521)', timestamp: 30.minutes.ago.to_i)
      end

      it 'does not raise on zero time difference' do
        expect { described_class.new(user.id, start_time, end_time).call }.not_to raise_error
      end
    end

    context 'with fewer than 3 points' do
      let!(:p1) do
        create(:point, user: user, latitude: 52.52, longitude: 13.405,
               lonlat: 'POINT(13.405 52.52)', timestamp: 30.minutes.ago.to_i)
      end

      it 'does not raise and returns 0' do
        result = described_class.new(user.id, start_time, end_time).call
        expect(result).to eq(0)
        expect(p1.reload.anomaly).not_to be true
      end
    end

    context 'returns count of marked anomalies' do
      let!(:bad) { create(:point, user: user, accuracy: 500, timestamp: 30.minutes.ago.to_i) }
      let!(:good) { create(:point, user: user, accuracy: 10, timestamp: 29.minutes.ago.to_i) }

      it 'returns the total count of anomalies marked' do
        result = described_class.new(user.id, start_time, end_time).call
        expect(result).to eq(1)
      end
    end

    context 'when user disables GPS filtering' do
      let(:user) { create(:user, settings: { 'gps_filtering_enabled' => false }) }
      let!(:terrible) { create(:point, user: user, accuracy: 5000, timestamp: 30.minutes.ago.to_i) }

      it 'returns 0 and leaves points untouched' do
        expect(described_class.new(user.id, start_time, end_time).call).to eq(0)
        expect(terrible.reload.anomaly).not_to be true
      end
    end

    context 'when user raises the accuracy threshold' do
      let(:user) { create(:user, settings: { 'gps_accuracy_threshold' => 500 }) }
      let!(:between_default_and_user) do
        create(:point, user: user, accuracy: 200, timestamp: 30.minutes.ago.to_i,
               latitude: 52.52, longitude: 13.405, lonlat: 'POINT(13.405 52.52)')
      end
      let!(:above_user_threshold) do
        create(:point, user: user, accuracy: 600, timestamp: 29.minutes.ago.to_i,
               latitude: 52.5201, longitude: 13.4051, lonlat: 'POINT(13.4051 52.5201)')
      end

      before { described_class.new(user.id, start_time, end_time).call }

      it 'keeps points below the user threshold' do
        expect(between_default_and_user.reload.anomaly).not_to be true
      end

      it 'still flags points above the user threshold' do
        expect(above_user_threshold.reload.anomaly).to be true
      end
    end
  end
end

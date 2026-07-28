# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::AnomalyFilter do
  let(:user) { create(:user) }
  let(:start_time) { 1.hour.ago.to_i }
  let(:end_time) { Time.current.to_i }

  describe '#call' do
    it 'bumps updated_at when flagging an anomaly so cached point reads invalidate' do
      point = create(:point, user: user, accuracy: 500, timestamp: 30.minutes.ago.to_i,
                             latitude: 52.52, longitude: 13.405, lonlat: 'POINT(13.405 52.52)')
      point.update_column(:updated_at, 2.days.ago)
      before_updated = point.reload.updated_at

      described_class.new(user.id, start_time, end_time).call

      expect(point.reload.anomaly).to be true
      expect(point.updated_at).to be > before_updated
    end

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

    context 'Pass 2: narrow realtime window does not rescan the whole month' do
      let(:base_lat) { 52.52 }
      let(:base_lon) { 13.405 }
      let(:month_start) { Time.current.beginning_of_month }
      let(:early_base) { (month_start + 2.days).to_i }
      let(:late_base) { (month_start + 20.days).to_i }

      def normal_point(timestamp)
        create(:point, user: user, latitude: base_lat, longitude: base_lon,
               lonlat: "POINT(#{base_lon} #{base_lat})", timestamp: timestamp, accuracy: 10)
      end

      def spike_point(timestamp)
        create(:point, user: user, latitude: base_lat + 10.0, longitude: base_lon + 10.0,
               lonlat: "POINT(#{base_lon + 10.0} #{base_lat + 10.0})", timestamp: timestamp, accuracy: 10)
      end

      let!(:early_before) { normal_point(early_base) }
      let!(:early_spike)  { spike_point(early_base + 60) }
      let!(:early_after)  { normal_point(early_base + 120) }

      let!(:late_before) { normal_point(late_base) }
      let!(:late_spike)  { spike_point(late_base + 60) }
      let!(:late_after)  { normal_point(late_base + 120) }

      before { described_class.new(user.id, late_spike.timestamp, late_spike.timestamp).call }

      it 'flags the spike inside the window using context points' do
        expect(late_spike.reload.anomaly).to be true
      end

      it 'leaves an earlier spike outside the window untouched' do
        expect(early_spike.reload.anomaly).not_to be true
      end
    end

    context 'Pass 3: Null Island (0,0)' do
      let(:start_time) { 2.hours.ago.to_i }
      let(:end_time) { Time.current.to_i }

      let!(:before_zero) do
        create(:point, user: user, latitude: 52.5, longitude: 13.4,
                       lonlat: 'POINT(13.4 52.5)', accuracy: 10, timestamp: 90.minutes.ago.to_i)
      end
      let!(:zero_run) do
        3.times.map do |i|
          create(:point, user: user, latitude: 0.0, longitude: 0.0,
                         lonlat: 'POINT(0.0 0.0)', accuracy: 10,
                         timestamp: (80 - (i * 10)).minutes.ago.to_i)
        end
      end
      let!(:after_zero) do
        create(:point, user: user, latitude: 52.5001, longitude: 13.4001,
                       lonlat: 'POINT(13.4001 52.5001)', accuracy: 10, timestamp: 40.minutes.ago.to_i)
      end

      before { described_class.new(user.id, start_time, end_time).call }

      it 'flags every point of a sustained (0,0) run' do
        expect(zero_run.map { |p| p.reload.anomaly }).to all(be(true))
      end

      it 'does not flag the surrounding real points' do
        expect(before_zero.reload.anomaly).not_to be true
        expect(after_zero.reload.anomaly).not_to be true
      end
    end
  end
end

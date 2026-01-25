# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TransportationModes::ModeClassifier do
  describe '#classify' do
    context 'stationary detection' do
      it 'classifies very low speed as stationary' do
        classifier = described_class.new(avg_speed_kmh: 0.5)
        expect(classifier.classify).to eq(:stationary)
      end

      it 'classifies zero speed as stationary' do
        classifier = described_class.new(avg_speed_kmh: 0)
        expect(classifier.classify).to eq(:stationary)
      end
    end

    context 'walking detection' do
      it 'classifies slow walking speed as walking' do
        classifier = described_class.new(avg_speed_kmh: 4)
        expect(classifier.classify).to eq(:walking)
      end

      it 'classifies brisk walking speed as walking' do
        classifier = described_class.new(avg_speed_kmh: 6)
        expect(classifier.classify).to eq(:walking)
      end
    end

    context 'running vs cycling distinction' do
      it 'classifies high acceleration in 7-20 km/h range as running' do
        classifier = described_class.new(avg_speed_kmh: 12, avg_acceleration: 0.4)
        expect(classifier.classify).to eq(:running)
      end

      it 'classifies low acceleration in 7-20 km/h range as cycling' do
        classifier = described_class.new(avg_speed_kmh: 15, avg_acceleration: 0.15)
        expect(classifier.classify).to eq(:cycling)
      end
    end

    context 'cycling vs driving distinction' do
      it 'classifies 25 km/h with low acceleration as cycling' do
        classifier = described_class.new(avg_speed_kmh: 25, avg_acceleration: 0.2)
        expect(classifier.classify).to eq(:cycling)
      end

      it 'classifies 25 km/h with high acceleration as driving' do
        classifier = described_class.new(avg_speed_kmh: 25, avg_acceleration: 0.6)
        expect(classifier.classify).to eq(:driving)
      end

      it 'classifies 40 km/h as driving' do
        classifier = described_class.new(avg_speed_kmh: 40, avg_acceleration: 0.3)
        expect(classifier.classify).to eq(:driving)
      end
    end

    context 'driving detection' do
      it 'classifies highway speed as driving' do
        classifier = described_class.new(avg_speed_kmh: 100, avg_acceleration: 0.3)
        expect(classifier.classify).to eq(:driving)
      end

      it 'classifies autobahn speed as driving' do
        classifier = described_class.new(avg_speed_kmh: 180, avg_acceleration: 0.4)
        expect(classifier.classify).to eq(:driving)
      end
    end

    context 'train detection' do
      it 'classifies high speed with very low acceleration as train' do
        classifier = described_class.new(
          avg_speed_kmh: 150,
          max_speed_kmh: 160,
          avg_acceleration: 0.1
        )
        expect(classifier.classify).to eq(:train)
      end
    end

    context 'flying detection' do
      it 'classifies very high speed as flying' do
        classifier = described_class.new(avg_speed_kmh: 800, max_speed_kmh: 850)
        expect(classifier.classify).to eq(:flying)
      end

      it 'classifies aircraft cruising speed as flying' do
        classifier = described_class.new(avg_speed_kmh: 500, max_speed_kmh: 600)
        expect(classifier.classify).to eq(:flying)
      end
    end
  end

  describe '#confidence' do
    context 'high confidence cases' do
      it 'returns high for stationary' do
        classifier = described_class.new(avg_speed_kmh: 0.5)
        expect(classifier.confidence).to eq(:high)
      end

      it 'returns high for flying' do
        classifier = described_class.new(avg_speed_kmh: 800, max_speed_kmh: 850)
        expect(classifier.confidence).to eq(:high)
      end

      it 'returns high for clear walking speed' do
        classifier = described_class.new(avg_speed_kmh: 5)
        expect(classifier.confidence).to eq(:high)
      end
    end

    context 'low confidence cases' do
      it 'returns low for ambiguous speed range' do
        classifier = described_class.new(avg_speed_kmh: 15, avg_acceleration: 0.25)
        expect(classifier.confidence).to eq(:low)
      end
    end
  end

  describe 'user threshold support' do
    context 'with custom walking_max_speed' do
      it 'uses user-defined walking max speed' do
        # Default walking max is 7, user sets it to 10
        classifier = described_class.new(
          avg_speed_kmh: 8,
          user_thresholds: { 'walking_max_speed' => 10 }
        )
        expect(classifier.classify).to eq(:walking)
      end

      it 'classifies above custom threshold as running/cycling' do
        classifier = described_class.new(
          avg_speed_kmh: 12,
          avg_acceleration: 0.1,
          user_thresholds: { 'walking_max_speed' => 10 }
        )
        expect(classifier.classify).to eq(:cycling)
      end
    end

    context 'with custom cycling_max_speed' do
      it 'uses user-defined cycling max speed' do
        # Default cycling max is 45, user sets it to 35
        classifier = described_class.new(
          avg_speed_kmh: 38,
          avg_acceleration: 0.2,
          user_thresholds: { 'cycling_max_speed' => 35 }
        )
        # Above 35 km/h should now be driving
        expect(classifier.classify).to eq(:driving)
      end
    end

    context 'with custom flying_min_speed' do
      it 'uses user-defined flying min speed' do
        # Default flying min is 150, user sets it to 100
        classifier = described_class.new(
          avg_speed_kmh: 120,
          max_speed_kmh: 160,
          user_thresholds: { 'flying_min_speed' => 100 }
        )
        expect(classifier.classify).to eq(:flying)
      end
    end

    context 'with expert thresholds' do
      it 'uses custom stationary_max_speed' do
        # Default stationary max is 1, user sets it to 2
        classifier = described_class.new(
          avg_speed_kmh: 1.5,
          user_expert_thresholds: { 'stationary_max_speed' => 2 }
        )
        expect(classifier.classify).to eq(:stationary)
      end

      it 'uses custom running_vs_cycling_accel' do
        # Default is 0.25, user sets it to 0.5
        # At 0.3 accel, default would classify as running, custom should classify as cycling
        classifier = described_class.new(
          avg_speed_kmh: 12,
          avg_acceleration: 0.3,
          user_expert_thresholds: { 'running_vs_cycling_accel' => 0.5 }
        )
        expect(classifier.classify).to eq(:cycling)
      end

      it 'uses custom train_min_speed' do
        # Default is 80, user sets it to 60
        classifier = described_class.new(
          avg_speed_kmh: 70,
          max_speed_kmh: 75,
          avg_acceleration: 0.1,
          user_expert_thresholds: { 'train_min_speed' => 60 }
        )
        expect(classifier.classify).to eq(:train)
      end
    end

    context 'with symbol keys' do
      it 'handles symbol keys in user_thresholds' do
        classifier = described_class.new(
          avg_speed_kmh: 8,
          user_thresholds: { walking_max_speed: 10 }
        )
        expect(classifier.classify).to eq(:walking)
      end
    end

    context 'with nil thresholds' do
      it 'uses defaults when user_thresholds is nil' do
        classifier = described_class.new(
          avg_speed_kmh: 5,
          user_thresholds: nil,
          user_expert_thresholds: nil
        )
        expect(classifier.classify).to eq(:walking)
      end
    end
  end
end

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
end

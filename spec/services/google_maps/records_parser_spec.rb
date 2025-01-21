# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GoogleMaps::RecordsParser do
  describe '#call' do
    subject(:parser) { described_class.new(import).call(locations) }

    let(:import) { create(:import) }
    let(:time) { DateTime.new(2025, 1, 1, 12, 0, 0) }
    let(:locations) do
      [
        {
          'timestampMs' => (time.to_f * 1000).to_i.to_s,
          'latitudeE7' => 123_456_789,
          'longitudeE7' => 123_456_789,
          'accuracy' => 10,
          'altitude' => 100,
          'verticalAccuracy' => 5,
          'activity' => [
            {
              'timestampMs' => (time.to_f * 1000).to_i.to_s,
              'activity' => [
                {
                  'type' => 'STILL',
                  'confidence' => 100
                }
              ]
            }
          ]
        }
      ]
    end

    context 'with regular timestamp' do
      let(:locations) { super()[0].merge('timestamp' => time.to_s).to_json }

      it 'creates a point' do
        expect { parser }.to change(Point, :count).by(1)
      end
    end

    context 'when point already exists' do
      let(:locations) do
        [
          super()[0].merge(
            'timestamp' => time.to_s,
            'latitudeE7' => 123_456_789,
            'longitudeE7' => 123_456_789
          )
        ]
      end

      before do
        create(
          :point,
          user: import.user,
          import: import,
          latitude: 12.3456789,
          longitude: 12.3456789,
          timestamp: time.to_i
        )
      end

      it 'does not create a point' do
        expect { parser }.not_to change(Point, :count)
      end
    end

    context 'with timestampMs in milliseconds' do
      let(:locations) do
        [super()[0].merge('timestampMs' => (time.to_f * 1000).to_i.to_s)]
      end

      it 'creates a point using milliseconds timestamp' do
        expect { parser }.to change(Point, :count).by(1)
      end
    end

    context 'with ISO 8601 timestamp' do
      let(:locations) do
        [super()[0].merge('timestamp' => time.iso8601)]
      end

      it 'parses ISO 8601 timestamp correctly' do
        expect { parser }.to change(Point, :count).by(1)
        created_point = Point.last
        expect(created_point.timestamp).to eq(time.to_i)
      end
    end

    context 'with timestamp in milliseconds' do
      let(:locations) do
        [super()[0].merge('timestamp' => (time.to_f * 1000).to_i.to_s)]
      end

      it 'parses millisecond timestamp correctly' do
        expect { parser }.to change(Point, :count).by(1)
        created_point = Point.last
        expect(created_point.timestamp).to eq(time.to_i)
      end
    end

    context 'with timestamp in seconds' do
      let(:locations) do
        [super()[0].merge('timestamp' => time.to_i.to_s)]
      end

      it 'parses second timestamp correctly' do
        expect { parser }.to change(Point, :count).by(1)
        created_point = Point.last
        expect(created_point.timestamp).to eq(time.to_i)
      end
    end
  end
end

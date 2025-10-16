# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GoogleMaps::RecordsImporter do
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
          'heading' => 270,
          'velocity' => 15,
          'batteryCharging' => true,
          'source' => 'GPS',
          'deviceTag' => 1234567890,
          'platformType' => 'ANDROID',
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
          lonlat: 'POINT(12.3456789 12.3456789)',
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

    context 'with additional Records.json schema fields' do
      let(:locations) do
        [
          {
            'timestamp' => time.iso8601,
            'latitudeE7' => 123_456_789,
            'longitudeE7' => 123_456_789,
            'accuracy' => 20,
            'altitude' => 150,
            'verticalAccuracy' => 10,
            'heading' => 270,
            'velocity' => 10,
            'batteryCharging' => true,
            'source' => 'WIFI',
            'deviceTag' => 1234567890,
            'platformType' => 'ANDROID'
          }
        ]
      end

      it 'extracts all supported fields' do
        expect { parser }.to change(Point, :count).by(1)

        created_point = Point.last
        expect(created_point.accuracy).to eq(20)
        expect(created_point.altitude).to eq(150)
        expect(created_point.vertical_accuracy).to eq(10)
        expect(created_point.course).to eq(270)
        expect(created_point.velocity).to eq('10')
        expect(created_point.battery).to eq(1) # true -> 1
      end

      it 'stores all fields in raw_data' do
        parser
        created_point = Point.last

        expect(created_point.raw_data['source']).to eq('WIFI')
        expect(created_point.raw_data['deviceTag']).to eq(1234567890)
        expect(created_point.raw_data['platformType']).to eq('ANDROID')
      end
    end

    context 'with batteryCharging false' do
      let(:locations) do
        [
          {
            'timestamp' => time.iso8601,
            'latitudeE7' => 123_456_789,
            'longitudeE7' => 123_456_789,
            'batteryCharging' => false
          }
        ]
      end

      it 'stores battery as 0' do
        expect { parser }.to change(Point, :count).by(1)
        expect(Point.last.battery).to eq(0)
      end
    end

    context 'with missing optional fields' do
      let(:locations) do
        [
          {
            'timestamp' => time.iso8601,
            'latitudeE7' => 123_456_789,
            'longitudeE7' => 123_456_789
          }
        ]
      end

      it 'handles missing fields gracefully' do
        expect { parser }.to change(Point, :count).by(1)

        created_point = Point.last
        expect(created_point.accuracy).to be_nil
        expect(created_point.vertical_accuracy).to be_nil
        expect(created_point.course).to be_nil
        expect(created_point.battery).to be_nil
      end
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GoogleMaps::RecordsParser do
  describe '#call' do
    subject(:parser) { described_class.new(import).call(json) }

    let(:import) { create(:import) }
    let(:time) { DateTime.new(2025, 1, 1, 12, 0, 0) }
    let(:json) do
      {
        'latitudeE7' => 123_456_789,
        'longitudeE7' => 123_456_789,
        'altitude' => 0,
        'velocity' => 0
      }
    end

    context 'with regular timestamp' do
      let(:json) { super().merge('timestamp' => time.to_s) }

      it 'creates a point' do
        expect { parser }.to change(Point, :count).by(1)
      end
    end

    context 'when point already exists' do
      let(:json) { super().merge('timestamp' => time.to_s) }

      before do
        create(
          :point, user: import.user, import:, latitude: 12.3456789, longitude: 12.3456789,
          timestamp: time.to_i
        )
      end

      it 'does not create a point' do
        expect { parser }.not_to change(Point, :count)
      end
    end

    context 'with timestampMs in milliseconds' do
      let(:json) { super().merge('timestampMs' => (time.to_f * 1000).to_i.to_s) }

      it 'creates a point using milliseconds timestamp' do
        expect { parser }.to change(Point, :count).by(1)
      end
    end

    context 'with ISO 8601 timestamp' do
      let(:json) { super().merge('timestamp' => time.iso8601) }

      it 'parses ISO 8601 timestamp correctly' do
        expect { parser }.to change(Point, :count).by(1)
        created_point = Point.last
        expect(created_point.timestamp).to eq(time.to_i)
      end
    end

    context 'with timestamp in milliseconds' do
      let(:json) { super().merge('timestamp' => (time.to_f * 1000).to_i.to_s) }

      it 'parses millisecond timestamp correctly' do
        expect { parser }.to change(Point, :count).by(1)
        created_point = Point.last
        expect(created_point.timestamp).to eq(time.to_i)
      end
    end

    context 'with timestamp in seconds' do
      let(:json) { super().merge('timestamp' => time.to_i.to_s) }

      it 'parses second timestamp correctly' do
        expect { parser }.to change(Point, :count).by(1)
        created_point = Point.last
        expect(created_point.timestamp).to eq(time.to_i)
      end
    end
  end
end

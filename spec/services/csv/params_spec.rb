# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Csv::Params do
  let(:user_id) { 1 }
  let(:import_id) { 1 }

  describe '#call' do
    context 'with decimal degrees and ISO 8601 timestamps' do
      let(:detection) do
        {
          columns: { latitude: 1, longitude: 2, timestamp: 0, altitude: 3, accuracy: 4, speed: 6 },
          coordinate_format: :decimal_degrees,
          timestamp_format: :iso8601,
          comma_decimals: false
        }
      end
      let(:row) { ['2024-06-15T10:30:00.000Z', '52.5200', '13.4050', '34.0', '8', '90', '1.5'] }

      it 'returns a point hash' do
        result = described_class.new(row, detection, user_id, import_id).call
        expect(result).not_to be_nil
      end

      it 'builds lonlat in POINT(lon lat) format' do
        result = described_class.new(row, detection, user_id, import_id).call
        expect(result[:lonlat]).to eq('POINT(13.405 52.52)')
      end

      it 'parses ISO 8601 timestamp as integer' do
        result = described_class.new(row, detection, user_id, import_id).call
        expect(result[:timestamp]).to eq(Time.zone.parse('2024-06-15T10:30:00Z').to_i)
      end

      it 'includes user_id and import_id' do
        result = described_class.new(row, detection, user_id, import_id).call
        expect(result[:user_id]).to eq(user_id)
        expect(result[:import_id]).to eq(import_id)
      end

      it 'extracts altitude' do
        result = described_class.new(row, detection, user_id, import_id).call
        expect(result[:altitude]).to eq(34.0)
      end

      it 'extracts speed as velocity' do
        result = described_class.new(row, detection, user_id, import_id).call
        expect(result[:velocity]).to eq(1.5)
      end
    end

    context 'with E7 integer coordinates' do
      let(:detection) do
        {
          columns: { latitude: 1, longitude: 2, timestamp: 0 },
          coordinate_format: :e7,
          timestamp_format: :iso8601,
          comma_decimals: false
        }
      end
      let(:row) { ['2024-06-15T10:30:00Z', '525200000', '134050000'] }

      it 'converts E7 to decimal degrees' do
        result = described_class.new(row, detection, user_id, import_id).call
        expect(result[:lonlat]).to include('13.405')
        expect(result[:lonlat]).to include('52.52')
      end
    end

    context 'with directional N/S E/W coordinates' do
      let(:detection) do
        {
          columns: { latitude: 0, longitude: 1, timestamp: 2 },
          coordinate_format: :directional,
          timestamp_format: :iso8601,
          comma_decimals: false
        }
      end

      it 'parses N suffix as positive' do
        row = ['52.520000N', '13.405000E', '2024-06-15T10:30:00Z']
        result = described_class.new(row, detection, user_id, import_id).call
        expect(result[:lonlat]).to include('13.405')
        expect(result[:lonlat]).to include('52.52')
      end

      it 'parses S suffix as negative latitude' do
        row = ['33.865000S', '151.209000E', '2024-06-15T10:30:00Z']
        result = described_class.new(row, detection, user_id, import_id).call
        expect(result[:lonlat]).to include('-33.865')
      end

      it 'parses W suffix as negative longitude' do
        row = ['40.712000N', '74.006000W', '2024-06-15T10:30:00Z']
        result = described_class.new(row, detection, user_id, import_id).call
        expect(result[:lonlat]).to include('-74.006')
      end
    end

    context 'with Unix timestamps' do
      let(:detection) do
        {
          columns: { latitude: 1, longitude: 2, timestamp: 3 },
          coordinate_format: :decimal_degrees,
          timestamp_format: :unix_seconds,
          comma_decimals: false
        }
      end
      let(:row) { ['phone1', '52.5200', '13.4050', '1718444200'] }

      it 'converts Unix seconds to integer' do
        result = described_class.new(row, detection, user_id, import_id).call
        expect(result[:timestamp]).to eq(1_718_444_200)
      end
    end

    context 'with comma decimals' do
      let(:detection) do
        {
          columns: { latitude: 1, longitude: 2, timestamp: 0 },
          coordinate_format: :decimal_degrees,
          timestamp_format: :iso8601,
          comma_decimals: true
        }
      end
      let(:row) { ['2024-06-15T10:30:00Z', '52,5200', '13,4050'] }

      it 'replaces comma with dot in coordinates' do
        result = described_class.new(row, detection, user_id, import_id).call
        expect(result[:lonlat]).to include('13.405')
        expect(result[:lonlat]).to include('52.52')
      end
    end

    context 'with missing required fields' do
      let(:detection) do
        {
          columns: { latitude: 0, longitude: 1, timestamp: 2 },
          coordinate_format: :decimal_degrees,
          timestamp_format: :iso8601,
          comma_decimals: false
        }
      end

      it 'returns nil for blank latitude' do
        row = ['', '13.405', '2024-06-15T10:30:00Z']
        result = described_class.new(row, detection, user_id, import_id).call
        expect(result).to be_nil
      end

      it 'returns nil for blank timestamp' do
        row = ['52.52', '13.405', '']
        result = described_class.new(row, detection, user_id, import_id).call
        expect(result).to be_nil
      end
    end
  end
end

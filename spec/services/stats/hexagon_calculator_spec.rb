# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Stats::HexagonCalculator do
  describe '#call' do
    subject(:calculate_hexagons) do
      described_class.new(user.id, year, month).call(h3_resolution: h3_resolution)
    end

    let(:user) { create(:user) }
    let(:year) { 2024 }
    let(:month) { 1 }
    let(:h3_resolution) { 8 }

    context 'when there are no points' do
      it 'returns empty array' do
        expect(calculate_hexagons).to eq([])
      end
    end

    context 'when there are points' do
      let(:timestamp1) { DateTime.new(year, month, 1, 12).to_i }
      let(:timestamp2) { DateTime.new(year, month, 1, 13).to_i }
      let!(:import) { create(:import, user:) }
      let!(:point1) do
        create(:point,
               user:,
               import:,
               timestamp: timestamp1,
               lonlat: 'POINT(14.452712811406352 52.107902115161316)')
      end
      let!(:point2) do
        create(:point,
               user:,
               import:,
               timestamp: timestamp2,
               lonlat: 'POINT(14.453712811406352 52.108902115161316)')
      end

      it 'returns H3 hexagon data' do
        result = calculate_hexagons

        expect(result).to be_an(Array)
        expect(result).not_to be_empty

        # Each record should have: [h3_index_string, point_count, earliest_timestamp, latest_timestamp]
        result.each do |record|
          expect(record).to be_an(Array)
          expect(record.size).to eq(4)
          expect(record[0]).to be_a(String) # H3 index as hex string
          expect(record[1]).to be_a(Integer) # Point count
          expect(record[2]).to be_a(Integer) # Earliest timestamp
          expect(record[3]).to be_a(Integer) # Latest timestamp
        end
      end

      it 'aggregates points correctly' do
        result = calculate_hexagons

        total_points = result.sum { |record| record[1] }
        expect(total_points).to eq(2)
      end

      context 'when there are too many hexagons' do
        let(:h3_resolution) { 15 } # Very high resolution to trigger MAX_HEXAGONS

        before do
          # Stub to simulate too many hexagons on first call, then acceptable on second
          allow_any_instance_of(described_class).to receive(:calculate_h3_indexes).and_call_original
          call_count = 0
          allow_any_instance_of(described_class).to receive(:calculate_h3_indexes) do |_instance, _points, _resolution|
            call_count += 1
            if call_count == 1
              # First call: return too many hexagons
              {}.tap do |hash|
                (described_class::MAX_HEXAGONS + 1).times do |i|
                  hash[i.to_s(16)] = [1, timestamp1, timestamp1]
                end
              end
            else
              # Second call with lower resolution: return acceptable amount
              { '8c2a1072b3f1fff' => [2, timestamp1, timestamp2] }
            end
          end
        end

        it 'recursively reduces resolution when too many hexagons are generated' do
          result = calculate_hexagons

          expect(result).to be_an(Array)
          expect(result).not_to be_empty
          # Should have successfully reduced the hexagon count
          expect(result.size).to be < described_class::MAX_HEXAGONS
        end
      end

      context 'when H3 raises an error' do
        before do
          allow(H3).to receive(:from_geo_coordinates).and_raise(StandardError, 'H3 error')
        end

        it 'raises PostGISError' do
          expect do
            calculate_hexagons
          end.to raise_error(Stats::HexagonCalculator::PostGISError, /Failed to calculate H3 hexagon centers/)
        end

        it 'reports the exception' do
          expect(ExceptionReporter).to receive(:call) if defined?(ExceptionReporter)

          expect { calculate_hexagons }.to raise_error(Stats::HexagonCalculator::PostGISError)
        end
      end
    end
  end
end

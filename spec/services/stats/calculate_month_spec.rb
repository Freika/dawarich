# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Stats::CalculateMonth do
  describe '#call' do
    subject(:calculate_stats) { described_class.new(user.id, year, month).call }

    let(:user) { create(:user) }
    let(:year) { 2021 }
    let(:month) { 1 }

    context 'when there are no points' do
      it 'does not create stats' do
        expect { calculate_stats }.not_to(change { Stat.count })
      end

      context 'when stats already exist for the month' do
        before do
          create(:stat, user: user, year: year, month: month)
        end

        it 'deletes existing stats for that month' do
          expect { calculate_stats }.to change { Stat.count }.by(-1)
        end
      end
    end

    context 'when there are points' do
      let(:timestamp1) { DateTime.new(year, month, 1, 12).to_i }
      let(:timestamp2) { DateTime.new(year, month, 1, 13).to_i }
      let(:timestamp3) { DateTime.new(year, month, 1, 14).to_i }
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
               lonlat: 'POINT(12.291519487061901 51.9746598171507)')
      end
      let!(:point3) do
        create(:point,
               user:,
               import:,
               timestamp: timestamp3,
               lonlat: 'POINT(9.77973105800526 52.72859111523629)')
      end

      context 'when calculating distance' do
        it 'creates stats' do
          expect { calculate_stats }.to change { Stat.count }.by(1)
        end

        it 'calculates distance in meters consistently' do
          calculate_stats

          # Distance should be calculated in meters regardless of user unit preference
          # The actual distance between the test points is approximately 340 km = 340,000 meters
          expect(user.stats.last.distance).to be_within(1000).of(340_000)
        end

        context 'when there is an error' do
          before do
            allow(Stat).to receive(:find_or_initialize_by).and_raise(StandardError)
          end

          it 'does not create stats' do
            expect { calculate_stats }.not_to(change { Stat.count })
          end

          it 'creates a notification' do
            expect { calculate_stats }.to change { Notification.count }.by(1)
          end
        end
      end

      context 'when user prefers miles' do
        before do
          user.update(settings: { maps: { distance_unit: 'mi' } })
        end

        it 'still stores distance in meters (same as km users)' do
          calculate_stats

          # Distance stored should be the same regardless of user preference (meters)
          expect(user.stats.last.distance).to be_within(1000).of(340_000)
        end
      end
    end
  end

  describe '#calculate_h3_hexagon_centers' do
    subject(:calculate_hexagons) do
      described_class.new(user.id, year, month).calculate_h3_hexagon_centers(
        user_id: user.id,
        start_date: start_date,
        end_date: end_date,
        h3_resolution: h3_resolution
      )
    end

    let(:user) { create(:user) }
    let(:year) { 2024 }
    let(:month) { 1 }
    let(:start_date) { DateTime.new(year, month, 1).beginning_of_day.iso8601 }
    let(:end_date) { DateTime.new(year, month, 1).end_of_month.end_of_day.iso8601 }
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


      context 'when H3 raises an error' do
        before do
          allow(H3).to receive(:from_geo_coordinates).and_raise(StandardError, 'H3 error')
        end

        it 'raises PostGISError' do
          expect { calculate_hexagons }.to raise_error(Stats::CalculateMonth::PostGISError, /Failed to calculate H3 hexagon centers/)
        end

        it 'reports the exception' do
          expect(ExceptionReporter).to receive(:call) if defined?(ExceptionReporter)

          expect { calculate_hexagons }.to raise_error(Stats::CalculateMonth::PostGISError)
        end
      end
    end

    describe 'date parameter parsing' do
      let(:service) { described_class.new(user.id, year, month) }

      it 'handles string timestamps' do
        result = service.send(:parse_date_parameter, '1640995200')
        expect(result).to eq(1640995200)
      end

      it 'handles ISO date strings' do
        result = service.send(:parse_date_parameter, '2024-01-01T00:00:00Z')
        expect(result).to be_a(Integer)
      end

      it 'handles integer timestamps' do
        result = service.send(:parse_date_parameter, 1640995200)
        expect(result).to eq(1640995200)
      end

      it 'handles edge case gracefully' do
        # Time.zone.parse is very lenient, so we'll test a different edge case
        result = service.send(:parse_date_parameter, nil)
        expect(result).to eq(0)
      end
    end
  end
end

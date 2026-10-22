# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Maps::BoundsCalculator do
  describe '.call' do
    subject(:calculate_bounds) do
      described_class.new(user:, start_date:, end_date:, import_id:, robust:).call
    end

    let(:user) { create(:user) }
    let(:start_date) { '2024-06-01T00:00:00Z' }
    let(:end_date) { '2024-06-30T23:59:59Z' }
    let(:import_id) { nil }
    let(:robust) { false }

    context 'with valid user and date range' do
      before do
        # Create test points within the date range
        create(:point, user:, latitude: 40.6, longitude: -74.1,
               timestamp: Time.new(2024, 6, 1, 12, 0).to_i)
        create(:point, user:, latitude: 40.8, longitude: -73.9,
               timestamp: Time.new(2024, 6, 30, 15, 0).to_i)
        create(:point, user:, latitude: 40.7, longitude: -74.0,
               timestamp: Time.new(2024, 6, 15, 10, 0).to_i)
      end

      it 'returns success with bounds data' do
        expect(calculate_bounds).to match(
          {
            success: true,
            data: {
              min_lat: 40.6,
              max_lat: 40.8,
              min_lng: -74.1,
              max_lng: -73.9,
              point_count: 3
            }
          }
        )
      end

      context 'with an import filter' do
        let(:selected_import) { create(:import, user:) }
        let(:import_id) { selected_import.id }

        before do
          create(:point, user:, import: selected_import, latitude: 41.2, longitude: -72.8,
                         timestamp: Time.new(2024, 6, 20, 10, 0).to_i)
        end

        it 'calculates bounds from the selected import only' do
          expect(calculate_bounds.dig(:data, :point_count)).to eq(1)
          expect(calculate_bounds.dig(:data, :min_lng)).to eq(-72.8)
        end
      end
    end

    context 'with no points in date range' do
      before do
        # Create points outside the date range
        create(:point, user:, latitude: 40.7, longitude: -74.0,
               timestamp: Time.new(2024, 5, 15, 10, 0).to_i)
      end

      it 'returns failure with no data message' do
        expect(calculate_bounds).to match(
          {
            success: false,
            error: 'No data found for the specified date range',
            point_count: 0
          }
        )
      end
    end

    context 'with robust bounds' do
      let(:robust) { true }
      let(:base_timestamp) { Time.utc(2024, 6, 15, 10, 0).to_i }

      before do
        55.times do |index|
          create(:point, user:, latitude: 52.5 + (index * 0.0001), longitude: 13.4 + (index * 0.0001),
                         timestamp: base_timestamp + index)
        end
      end

      it 'excludes an isolated GPS outlier but counts every point' do
        create(:point, user:, latitude: 40.7, longitude: -74.0, timestamp: base_timestamp + 100)

        expect(calculate_bounds.dig(:data, :point_count)).to eq(56)
        expect(calculate_bounds.dig(:data, :min_lng)).to be > 13
      end

      it 'retains a distant location with two Points' do
        2.times do |index|
          create(:point, user:, latitude: 40.7 + (index * 0.0001), longitude: -74.0 + (index * 0.0001),
                         timestamp: base_timestamp + 100 + index)
        end

        expect(calculate_bounds.dig(:data, :point_count)).to eq(57)
        expect(calculate_bounds.dig(:data, :min_lng)).to eq(-74.0)
      end

      it 'retains a sparse trip spread across adjacent cells' do
        8.times do |index|
          create(:point, user:, latitude: 40.2 + ((index / 4) * 2.1) + (index * 0.0001),
                         longitude: -74.2 + (((index / 2) % 2) * 2.1) + (index * 0.0001),
                         timestamp: base_timestamp + 100 + index)
        end

        expect(calculate_bounds.dig(:data, :point_count)).to eq(63)
        expect(calculate_bounds.dig(:data, :min_lng)).to be < -74
      end

      it 'ignores legacy points without coordinates' do
        point = create(:point, user:, latitude: 40.7, longitude: -74.0, timestamp: base_timestamp + 100)
        point.update_column(:lonlat, nil)

        expect(calculate_bounds.dig(:data, :point_count)).to eq(55)
        expect(calculate_bounds.dig(:data, :min_lng)).to be > 13
      end
    end

    context 'with a sparse robust range' do
      let(:robust) { true }

      it 'keeps both locations when the range has too few points for outlier detection' do
        create(:point, user:, latitude: 52.5, longitude: 13.4, timestamp: Time.utc(2024, 6, 15).to_i)
        create(:point, user:, latitude: 40.7, longitude: -74.0, timestamp: Time.utc(2024, 6, 16).to_i)

        expect(calculate_bounds.dig(:data, :min_lng)).to eq(-74.0)
      end

      it 'bounds the expensive aggregation with a database statement timeout' do
        create(:point, user:, latitude: 52.5, longitude: 13.4, timestamp: Time.utc(2024, 6, 15).to_i)
        statements = []
        subscriber = ->(_name, _start, _finish, _id, payload) { statements << payload[:sql] }

        ActiveSupport::Notifications.subscribed(subscriber, 'sql.active_record') { calculate_bounds }

        expect(statements).to include('SET LOCAL statement_timeout = 5000')
      end

      it 'samples the time index when the full aggregation times out' do
        create(:point, user:, latitude: 52.5, longitude: 13.4, timestamp: Time.utc(2024, 6, 15).to_i)
        calculator = described_class.new(user:, start_date:, end_date:, robust: true)
        allow(calculator).to receive(:execute_cell_bounds_query).and_raise(ActiveRecord::QueryCanceled)

        result = calculator.call

        expect(result).to include(success: true)
        expect(result[:data]).to include(min_lng: 13.4, point_count: nil, approximate: true)
      end
    end

    context 'with no user' do
      let(:user) { nil }

      it 'raises NoUserFoundError' do
        expect { calculate_bounds }.to raise_error(
          Maps::BoundsCalculator::NoUserFoundError,
          'No user found'
        )
      end
    end

    context 'with no start date' do
      let(:start_date) { nil }

      it 'raises NoDateRangeError' do
        expect { calculate_bounds }.to raise_error(
          Maps::BoundsCalculator::NoDateRangeError,
          'No date range specified'
        )
      end
    end

    context 'with no end date' do
      let(:end_date) { nil }

      it 'raises NoDateRangeError' do
        expect { calculate_bounds }.to raise_error(
          Maps::BoundsCalculator::NoDateRangeError,
          'No date range specified'
        )
      end
    end

    context 'with invalid date parsing' do
      let(:start_date) { 'invalid-date' }

      it 'raises ArgumentError for invalid dates' do
        expect { calculate_bounds }.to raise_error(ArgumentError, 'Invalid date format: invalid-date')
      end
    end

    context 'with timestamp format dates' do
      let(:start_date) { 1_717_200_000 }
      let(:end_date) { 1_719_791_999 }

      before do
        create(:point, user:, latitude: 41.0, longitude: -74.5,
               timestamp: Time.new(2024, 6, 5, 9, 0).to_i)
      end

      it 'handles timestamp format correctly' do
        result = calculate_bounds
        expect(result[:success]).to be true
        expect(result[:data][:point_count]).to eq(1)
      end
    end

    context 'query count' do
      before do
        create(:point, user:, latitude: 40.7, longitude: -74.0,
               timestamp: Time.new(2024, 6, 15, 10, 0).to_i)
      end

      it 'issues exactly one SQL query against points per call' do
        query_count = 0
        counter = lambda do |_name, _start, _finish, _id, payload|
          query_count += 1 unless payload[:name].in?(%w[SCHEMA TRANSACTION])
        end

        ActiveSupport::Notifications.subscribed(counter, 'sql.active_record') do
          calculate_bounds
        end

        expect(query_count).to eq(1)
      end
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Maps::BoundsCalculator do
  describe '.call' do
    subject(:calculate_bounds) do
      described_class.new(
        target_user: target_user,
        start_date: start_date,
        end_date: end_date
      ).call
    end

    let(:user) { create(:user) }
    let(:target_user) { user }
    let(:start_date) { '2024-06-01T00:00:00Z' }
    let(:end_date) { '2024-06-30T23:59:59Z' }

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

    context 'with no user' do
      let(:target_user) { nil }

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

    context 'with invalid date format' do
      let(:start_date) { 'invalid-date' }

      it 'raises InvalidDateFormatError' do
        expect { calculate_bounds }.to raise_error(
          Maps::DateParameterCoercer::InvalidDateFormatError
        )
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
  end
end

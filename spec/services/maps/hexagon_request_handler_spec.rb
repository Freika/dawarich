# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Maps::HexagonRequestHandler do
  describe '.call' do
    subject(:handle_request) do
      described_class.new(
        params: params,
        user: user,
        stat: stat,
        start_date: start_date,
        end_date: end_date
      ).call
    end

    let(:user) { create(:user) }

    context 'with authenticated user but no pre-calculated data' do
      let(:stat) { nil }
      let(:start_date) { '2024-06-01T00:00:00Z' }
      let(:end_date) { '2024-06-30T23:59:59Z' }
      let(:params) do
        ActionController::Parameters.new(
          {
            min_lon: -74.1,
            min_lat: 40.6,
            max_lon: -73.9,
            max_lat: 40.8,
            start_date: start_date,
            end_date: end_date
          }
        )
      end

      it 'returns empty feature collection when no pre-calculated data' do
        result = handle_request

        expect(result).to be_a(Hash)
        expect(result['type']).to eq('FeatureCollection')
        expect(result['features']).to eq([])
        expect(result['metadata']['hexagon_count']).to eq(0)
        expect(result['metadata']['source']).to eq('pre_calculated')
      end
    end

    context 'with public sharing UUID and pre-calculated centers' do
      let(:pre_calculated_centers) do
        {
          '8a1fb46622dffff' => [5, 1_717_200_000, 1_717_203_600],
          '8a1fb46622e7fff' => [3, 1_717_210_000, 1_717_213_600]
        }
      end
      let(:stat) do
        create(:stat, :with_sharing_enabled, user:, year: 2024, month: 6,
               h3_hex_ids: pre_calculated_centers)
      end
      let(:start_date) { Date.new(2024, 6, 1).beginning_of_day.iso8601 }
      let(:end_date) { Date.new(2024, 6, 1).end_of_month.end_of_day.iso8601 }
      let(:params) do
        ActionController::Parameters.new(
          {
            uuid: stat.sharing_uuid,
            min_lon: -74.1,
            min_lat: 40.6,
            max_lon: -73.9,
            max_lat: 40.8
          }
        )
      end

      it 'returns pre-calculated hexagon data' do
        result = handle_request

        expect(result['type']).to eq('FeatureCollection')
        expect(result['features'].length).to eq(2)
        expect(result['metadata']['pre_calculated']).to be true
        expect(result['metadata']['user_id']).to eq(user.id)
      end
    end

    context 'with public sharing UUID but no pre-calculated centers' do
      let(:stat) { create(:stat, :with_sharing_enabled, user:, year: 2024, month: 6) }
      let(:start_date) { Date.new(2024, 6, 1).beginning_of_day.iso8601 }
      let(:end_date) { Date.new(2024, 6, 1).end_of_month.end_of_day.iso8601 }
      let(:params) do
        ActionController::Parameters.new(
          {
            uuid: stat.sharing_uuid,
            min_lon: -74.1,
            min_lat: 40.6,
            max_lon: -73.9,
            max_lat: 40.8
          }
        )
      end

      it 'returns empty feature collection when no pre-calculated centers' do
        result = handle_request

        expect(result['type']).to eq('FeatureCollection')
        expect(result['features']).to eq([])
        expect(result['metadata']['hexagon_count']).to eq(0)
        expect(result['metadata']['source']).to eq('pre_calculated')
      end
    end

    context 'with stat containing empty h3_hex_ids data' do
      let(:stat) do
        create(:stat, :with_sharing_enabled, user:, year: 2024, month: 6,
               h3_hex_ids: {})
      end
      let(:start_date) { Date.new(2024, 6, 1).beginning_of_day.iso8601 }
      let(:end_date) { Date.new(2024, 6, 1).end_of_month.end_of_day.iso8601 }
      let(:params) do
        ActionController::Parameters.new(
          {
            uuid: stat.sharing_uuid,
            min_lon: -74.1,
            min_lat: 40.6,
            max_lon: -73.9,
            max_lat: 40.8
          }
        )
      end

      it 'returns empty feature collection for empty data' do
        result = handle_request

        expect(result['type']).to eq('FeatureCollection')
        expect(result['features']).to eq([])
        expect(result['metadata']['hexagon_count']).to eq(0)
        expect(result['metadata']['source']).to eq('pre_calculated')
      end
    end
  end
end

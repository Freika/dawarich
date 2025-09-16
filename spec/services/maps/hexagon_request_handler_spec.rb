# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Maps::HexagonRequestHandler do
  describe '.call' do
    subject(:handle_request) do
      described_class.call(
        params: params,
        current_api_user: current_api_user
      )
    end

    let(:user) { create(:user) }
    let(:current_api_user) { user }

    before do
      stub_request(:any, 'https://api.github.com/repos/Freika/dawarich/tags')
        .to_return(status: 200, body: '[{"name": "1.0.0"}]', headers: {})
    end

    context 'with authenticated user and bounding box params' do
      let(:params) do
        ActionController::Parameters.new({
          min_lon: -74.1,
          min_lat: 40.6,
          max_lon: -73.9,
          max_lat: 40.8,
          hex_size: 1000,
          start_date: '2024-06-01T00:00:00Z',
          end_date: '2024-06-30T23:59:59Z'
        })
      end

      before do
        # Create test points within the date range and bounding box
        10.times do |i|
          create(:point,
                 user:,
                 latitude: 40.7 + (i * 0.001),
                 longitude: -74.0 + (i * 0.001),
                 timestamp: Time.new(2024, 6, 15, 12, i).to_i)
        end
      end

      it 'returns on-the-fly hexagon calculation' do
        result = handle_request

        expect(result).to be_a(Hash)
        expect(result['type']).to eq('FeatureCollection')
        expect(result['features']).to be_an(Array)
        expect(result['metadata']).to be_present
      end
    end

    context 'with public sharing UUID and pre-calculated centers' do
      let(:pre_calculated_centers) do
        [
          [-74.0, 40.7, 1_717_200_000, 1_717_203_600],
          [-74.01, 40.71, 1_717_210_000, 1_717_213_600]
        ]
      end
      let(:stat) do
        create(:stat, :with_sharing_enabled, user:, year: 2024, month: 6,
               hexagon_centers: pre_calculated_centers)
      end
      let(:params) do
        ActionController::Parameters.new({
          uuid: stat.sharing_uuid,
          min_lon: -74.1,
          min_lat: 40.6,
          max_lon: -73.9,
          max_lat: 40.8,
          hex_size: 1000
        })
      end
      let(:current_api_user) { nil }

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
      let(:params) do
        ActionController::Parameters.new({
          uuid: stat.sharing_uuid,
          min_lon: -74.1,
          min_lat: 40.6,
          max_lon: -73.9,
          max_lat: 40.8,
          hex_size: 1000
        })
      end
      let(:current_api_user) { nil }

      before do
        # Create test points for the stat's month
        5.times do |i|
          create(:point,
                 user:,
                 latitude: 40.7 + (i * 0.001),
                 longitude: -74.0 + (i * 0.001),
                 timestamp: Time.new(2024, 6, 15, 12, i).to_i)
        end
      end

      it 'falls back to on-the-fly calculation' do
        result = handle_request

        expect(result['type']).to eq('FeatureCollection')
        expect(result['features']).to be_an(Array)
        expect(result['metadata']).to be_present
        expect(result['metadata']['pre_calculated']).to be_falsy
      end
    end

    context 'with legacy area_too_large that can be recalculated' do
      let(:stat) do
        create(:stat, :with_sharing_enabled, user:, year: 2024, month: 6,
               hexagon_centers: { 'area_too_large' => true })
      end
      let(:params) do
        ActionController::Parameters.new({
          uuid: stat.sharing_uuid,
          min_lon: -74.1,
          min_lat: 40.6,
          max_lon: -73.9,
          max_lat: 40.8,
          hex_size: 1000
        })
      end
      let(:current_api_user) { nil }

      before do
        # Mock successful recalculation
        allow_any_instance_of(Stats::CalculateMonth).to receive(:calculate_hexagon_centers)
          .and_return([[-74.0, 40.7, 1_717_200_000, 1_717_203_600]])
      end

      it 'recalculates and returns pre-calculated data' do
        expect(stat).to receive(:update).with(
          hexagon_centers: [[-74.0, 40.7, 1_717_200_000, 1_717_203_600]]
        )

        result = handle_request

        expect(result['type']).to eq('FeatureCollection')
        expect(result['features'].length).to eq(1)
        expect(result['metadata']['pre_calculated']).to be true
      end
    end

    context 'error handling' do
      let(:params) do
        ActionController::Parameters.new({
          uuid: 'invalid-uuid'
        })
      end
      let(:current_api_user) { nil }

      it 'raises SharedStatsNotFoundError for invalid UUID' do
        expect { handle_request }.to raise_error(
          Maps::HexagonContextResolver::SharedStatsNotFoundError
        )
      end
    end
  end
end
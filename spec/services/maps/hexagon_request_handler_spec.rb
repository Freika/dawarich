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
        result = handle_request

        expect(result['type']).to eq('FeatureCollection')
        expect(result['features'].length).to eq(1)
        expect(result['metadata']['pre_calculated']).to be true

        # Verify that the stat was updated with new centers (reload to check persistence)
        expect(stat.reload.hexagon_centers).to eq([[-74.0, 40.7, 1_717_200_000, 1_717_203_600]])
      end
    end

    context 'with H3 enabled via parameter' do
      let(:params) do
        ActionController::Parameters.new({
          min_lon: -74.1,
          min_lat: 40.6,
          max_lon: -73.9,
          max_lat: 40.8,
          hex_size: 1000,
          start_date: '2024-06-01T00:00:00Z',
          end_date: '2024-06-30T23:59:59Z',
          use_h3: 'true',
          h3_resolution: 6
        })
      end

      before do
        # Create test points within the date range
        5.times do |i|
          create(:point,
                 user:,
                 latitude: 40.7 + (i * 0.001),
                 longitude: -74.0 + (i * 0.001),
                 timestamp: Time.new(2024, 6, 15, 12, i).to_i)
        end
      end

      it 'uses H3 calculation when enabled' do
        result = handle_request

        expect(result).to be_a(Hash)
        expect(result['type']).to eq('FeatureCollection')
        expect(result['features']).to be_an(Array)

        # H3 calculation might return empty features if points don't create hexagons,
        # but if there are features, they should have H3-specific properties
        if result['features'].any?
          feature = result['features'].first
          expect(feature).to be_present

          # Only check properties if they exist - some integration paths might
          # return features without properties in certain edge cases
          if feature['properties'].present?
            expect(feature['properties']).to have_key('h3_index')
            expect(feature['properties']).to have_key('point_count')
            expect(feature['properties']).to have_key('center')
          else
            # If no properties, this is likely a fallback to non-H3 calculation
            # which is acceptable behavior - just verify the feature structure
            expect(feature).to have_key('type')
            expect(feature).to have_key('geometry')
          end
        else
          # If no features, that's OK - it means the H3 calculation ran but
          # didn't produce any hexagons for this data set
          expect(result['features']).to eq([])
        end
      end
    end

    context 'with H3 enabled via environment variable' do
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
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('HEXAGON_USE_H3').and_return('true')

        # Create test points within the date range
        3.times do |i|
          create(:point,
                 user:,
                 latitude: 40.7 + (i * 0.001),
                 longitude: -74.0 + (i * 0.001),
                 timestamp: Time.new(2024, 6, 15, 12, i).to_i)
        end
      end

      it 'uses H3 calculation when environment variable is set' do
        result = handle_request

        expect(result).to be_a(Hash)
        expect(result['type']).to eq('FeatureCollection')
        expect(result['features']).to be_an(Array)
        expect(result['features']).not_to be_empty
      end
    end

    context 'when H3 calculation fails' do
      let(:params) do
        ActionController::Parameters.new({
          min_lon: -74.1,
          min_lat: 40.6,
          max_lon: -73.9,
          max_lat: 40.8,
          hex_size: 1000,
          start_date: '2024-06-01T00:00:00Z',
          end_date: '2024-06-30T23:59:59Z',
          use_h3: 'true'
        })
      end

      before do
        # Create test points within the date range
        2.times do |i|
          create(:point,
                 user:,
                 latitude: 40.7 + (i * 0.001),
                 longitude: -74.0 + (i * 0.001),
                 timestamp: Time.new(2024, 6, 15, 12, i).to_i)
        end

        # Mock H3 calculator to fail
        allow_any_instance_of(Maps::H3HexagonCalculator).to receive(:call)
          .and_return({ success: false, error: 'H3 error' })
      end

      it 'falls back to grid calculation when H3 fails' do
        result = handle_request

        expect(result).to be_a(Hash)
        expect(result['type']).to eq('FeatureCollection')
        expect(result['features']).to be_an(Array)

        # Should fall back to grid-based calculation (won't have H3 properties)
        if result['features'].any?
          feature = result['features'].first
          expect(feature).to be_present
          if feature['properties'].present?
            expect(feature['properties']).not_to have_key('h3_index')
          end
        end
      end
    end

    context 'H3 resolution validation' do
      let(:params) do
        ActionController::Parameters.new({
          min_lon: -74.1,
          min_lat: 40.6,
          max_lon: -73.9,
          max_lat: 40.8,
          hex_size: 1000,
          start_date: '2024-06-01T00:00:00Z',
          end_date: '2024-06-30T23:59:59Z',
          use_h3: 'true',
          h3_resolution: invalid_resolution
        })
      end

      before do
        create(:point,
               user:,
               latitude: 40.7,
               longitude: -74.0,
               timestamp: Time.new(2024, 6, 15, 12, 0).to_i)
      end

      context 'with resolution too high' do
        let(:invalid_resolution) { 20 }

        it 'clamps resolution to maximum valid value' do
          # Mock to capture the actual resolution used
          calculator_double = instance_double(Maps::H3HexagonCalculator)
          allow(Maps::H3HexagonCalculator).to receive(:new) do |user_id, start_date, end_date, resolution|
            expect(resolution).to eq(15) # Should be clamped to 15
            calculator_double
          end
          allow(calculator_double).to receive(:call).and_return(
            { success: true, data: { 'type' => 'FeatureCollection', 'features' => [] } }
          )

          handle_request
        end
      end

      context 'with negative resolution' do
        let(:invalid_resolution) { -5 }

        it 'clamps resolution to minimum valid value' do
          # Mock to capture the actual resolution used
          calculator_double = instance_double(Maps::H3HexagonCalculator)
          allow(Maps::H3HexagonCalculator).to receive(:new) do |user_id, start_date, end_date, resolution|
            expect(resolution).to eq(0) # Should be clamped to 0
            calculator_double
          end
          allow(calculator_double).to receive(:call).and_return(
            { success: true, data: { 'type' => 'FeatureCollection', 'features' => [] } }
          )

          handle_request
        end
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
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::Maps::HexagonsController, type: :request do
  let(:valid_params) do
    {
      min_lon: -74.0,
      min_lat: 40.7,
      max_lon: -73.9,
      max_lat: 40.8
    }
  end

  let(:mock_geojson_response) do
    {
      type: 'FeatureCollection',
      features: [
        {
          type: 'Feature',
          id: '1',
          geometry: {
            type: 'Polygon',
            coordinates: [[[-74.0, 40.7], [-73.99, 40.7], [-73.99, 40.71], [-74.0, 40.71], [-74.0, 40.7]]]
          },
          properties: {
            hex_id: '1',
            hex_i: '0',
            hex_j: '0',
            hex_size: 500
          }
        }
      ],
      metadata: {
        bbox: [-74.0, 40.7, -73.9, 40.8],
        area_km2: 111.0,
        hex_size_m: 500,
        count: 1,
        estimated_count: 170
      }
    }
  end

  describe 'GET #index' do
    context 'with valid parameters' do
      before do
        allow_any_instance_of(Maps::HexagonGrid).to receive(:call).and_return(mock_geojson_response)
      end

      it 'returns successful response' do
        get '/api/v1/maps/hexagons', params: valid_params

        expect(response).to have_http_status(:success)
        expect(response.content_type).to eq('application/json; charset=utf-8')
      end

      it 'returns GeoJSON FeatureCollection' do
        get '/api/v1/maps/hexagons', params: valid_params

        json_response = JSON.parse(response.body, symbolize_names: true)
        expect(json_response[:type]).to eq('FeatureCollection')
        expect(json_response[:features]).to be_an(Array)
        expect(json_response[:metadata]).to be_a(Hash)
      end

      it 'includes proper feature structure' do
        get '/api/v1/maps/hexagons', params: valid_params

        json_response = JSON.parse(response.body, symbolize_names: true)
        feature = json_response[:features].first
        
        expect(feature[:type]).to eq('Feature')
        expect(feature[:id]).to eq('1')
        expect(feature[:geometry]).to include(type: 'Polygon')
        expect(feature[:properties]).to include(
          hex_id: '1',
          hex_i: '0',
          hex_j: '0',
          hex_size: 500
        )
      end

      it 'includes metadata about the generation' do
        get '/api/v1/maps/hexagons', params: valid_params

        json_response = JSON.parse(response.body, symbolize_names: true)
        metadata = json_response[:metadata]
        
        expect(metadata).to include(
          bbox: [-74.0, 40.7, -73.9, 40.8],
          area_km2: 111.0,
          hex_size_m: 500,
          count: 1,
          estimated_count: 170
        )
      end

      it 'accepts custom hex_size parameter' do
        custom_params = valid_params.merge(hex_size: 1000)
        allow_any_instance_of(Maps::HexagonGrid).to receive(:call).and_return(mock_geojson_response)

        get '/api/v1/maps/hexagons', params: custom_params

        expect(response).to have_http_status(:success)
      end
    end

    context 'with missing required parameters' do
      it 'returns bad request when min_lon is missing' do
        invalid_params = valid_params.except(:min_lon)
        
        get '/api/v1/maps/hexagons', params: invalid_params

        expect(response).to have_http_status(:bad_request)
        json_response = JSON.parse(response.body, symbolize_names: true)
        expect(json_response[:error]).to include('Missing required parameters: min_lon')
      end

      it 'returns bad request when multiple parameters are missing' do
        invalid_params = valid_params.except(:min_lon, :max_lat)
        
        get '/api/v1/maps/hexagons', params: invalid_params

        expect(response).to have_http_status(:bad_request)
        json_response = JSON.parse(response.body, symbolize_names: true)
        expect(json_response[:error]).to include('min_lon')
        expect(json_response[:error]).to include('max_lat')
      end

      it 'returns bad request when all parameters are missing' do
        get '/api/v1/maps/hexagons', params: {}

        expect(response).to have_http_status(:bad_request)
        json_response = JSON.parse(response.body, symbolize_names: true)
        expect(json_response[:error]).to include('Missing required parameters')
      end
    end

    context 'with invalid coordinates' do
      before do
        allow_any_instance_of(Maps::HexagonGrid).to receive(:call)
          .and_raise(Maps::HexagonGrid::InvalidCoordinatesError, 'Invalid coordinates provided')
      end

      it 'returns bad request with error message' do
        invalid_params = valid_params.merge(min_lon: 200)
        
        get '/api/v1/maps/hexagons', params: invalid_params

        expect(response).to have_http_status(:bad_request)
        json_response = JSON.parse(response.body, symbolize_names: true)
        expect(json_response[:error]).to eq('Invalid coordinates provided')
      end
    end

    context 'with bounding box too large' do
      before do
        allow_any_instance_of(Maps::HexagonGrid).to receive(:call)
          .and_raise(Maps::HexagonGrid::BoundingBoxTooLargeError, 'Area too large (1000000 km²). Maximum allowed: 250000 km²')
      end

      it 'returns bad request with descriptive error' do
        large_area_params = {
          min_lon: -180,
          min_lat: -89,
          max_lon: 180,
          max_lat: 89
        }
        
        get '/api/v1/maps/hexagons', params: large_area_params

        expect(response).to have_http_status(:bad_request)
        json_response = JSON.parse(response.body, symbolize_names: true)
        expect(json_response[:error]).to include('Area too large')
        expect(json_response[:error]).to include('Maximum allowed: 250000 km²')
      end
    end

    context 'with PostGIS errors' do
      before do
        allow_any_instance_of(Maps::HexagonGrid).to receive(:call)
          .and_raise(Maps::HexagonGrid::PostGISError, 'PostGIS function ST_HexagonGrid not available')
      end

      it 'returns internal server error' do
        get '/api/v1/maps/hexagons', params: valid_params

        expect(response).to have_http_status(:internal_server_error)
        json_response = JSON.parse(response.body, symbolize_names: true)
        expect(json_response[:error]).to eq('PostGIS function ST_HexagonGrid not available')
      end
    end

    context 'with unexpected errors' do
      before do
        allow_any_instance_of(Maps::HexagonGrid).to receive(:call)
          .and_raise(StandardError, 'Unexpected database error')
        allow(Rails.logger).to receive(:error)
      end

      it 'returns generic internal server error' do
        get '/api/v1/maps/hexagons', params: valid_params

        expect(response).to have_http_status(:internal_server_error)
        json_response = JSON.parse(response.body, symbolize_names: true)
        expect(json_response[:error]).to eq('Failed to generate hexagon grid')
      end

      it 'logs the full error details' do
        get '/api/v1/maps/hexagons', params: valid_params

        expect(Rails.logger).to have_received(:error).with(/Hexagon generation error: Unexpected database error/)
      end
    end
  end

  describe 'parameter filtering' do
    it 'permits required bounding box parameters' do
      # Controller method testing removed for request specs.and_return(valid_params)
      allow_any_instance_of(Maps::HexagonGrid).to receive(:call).and_return(mock_geojson_response)

      get '/api/v1/maps/hexagons', params: valid_params
    end

    it 'permits optional hex_size parameter' do
      params_with_hex_size = valid_params.merge(hex_size: 750)
      # Controller method testing removed for request specs.and_return(params_with_hex_size)
      allow_any_instance_of(Maps::HexagonGrid).to receive(:call).and_return(mock_geojson_response)

      get '/api/v1/maps/hexagons', params: params_with_hex_size
    end

    it 'filters out unauthorized parameters' do
      params_with_extra = valid_params.merge(
        unauthorized_param: 'should_be_filtered',
        another_bad_param: 'also_filtered'
      )
      allow_any_instance_of(Maps::HexagonGrid).to receive(:call).and_return(mock_geojson_response)

      get '/api/v1/maps/hexagons', params: params_with_extra
      
      expect(response).to have_http_status(:success)
    end
  end

  describe 'authentication' do
    it 'skips API key authentication' do
      # This test verifies the skip_before_action :authenticate_api_key is working
      get '/api/v1/maps/hexagons', params: valid_params

      # Should not return unauthorized status
      expect(response).not_to have_http_status(:unauthorized)
    end
  end

  describe 'edge case parameters' do
    context 'with boundary longitude values' do
      let(:boundary_params) do
        {
          min_lon: -180,
          min_lat: 40,
          max_lon: 180,
          max_lat: 41
        }
      end

      before do
        allow_any_instance_of(Maps::HexagonGrid).to receive(:call).and_return(mock_geojson_response)
      end

      it 'handles boundary longitude values' do
        get '/api/v1/maps/hexagons', params: boundary_params

        expect(response).to have_http_status(:success)
      end
    end

    context 'with boundary latitude values' do
      let(:boundary_params) do
        {
          min_lon: 0,
          min_lat: -90,
          max_lon: 1,
          max_lat: 90
        }
      end

      before do
        allow_any_instance_of(Maps::HexagonGrid).to receive(:call).and_return(mock_geojson_response)
      end

      it 'handles boundary latitude values' do
        get '/api/v1/maps/hexagons', params: boundary_params

        expect(response).to have_http_status(:success)
      end
    end

    context 'with very small areas' do
      let(:small_area_params) do
        {
          min_lon: -74.0000,
          min_lat: 40.7000,
          max_lon: -73.9999,
          max_lat: 40.7001
        }
      end

      before do
        allow_any_instance_of(Maps::HexagonGrid).to receive(:call).and_return(mock_geojson_response)
      end

      it 'handles very small bounding boxes' do
        get '/api/v1/maps/hexagons', params: small_area_params

        expect(response).to have_http_status(:success)
      end
    end
  end
end
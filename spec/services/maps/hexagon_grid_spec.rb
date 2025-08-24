# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Maps::HexagonGrid do
  let(:valid_params) do
    {
      min_lon: -74.0,
      min_lat: 40.7,
      max_lon: -73.9,  
      max_lat: 40.8
    }
  end

  describe '#initialize' do
    it 'sets default hex_size when not provided' do
      service = described_class.new(valid_params)
      
      expect(service.hex_size).to eq(described_class::DEFAULT_HEX_SIZE)
    end

    it 'uses provided hex_size' do
      service = described_class.new(valid_params.merge(hex_size: 1000))
      
      expect(service.hex_size).to eq(1000)
    end

    it 'converts string parameters to floats' do
      string_params = valid_params.transform_values(&:to_s)
      service = described_class.new(string_params)
      
      expect(service.min_lon).to eq(-74.0)
      expect(service.min_lat).to eq(40.7)
      expect(service.max_lon).to eq(-73.9)
      expect(service.max_lat).to eq(40.8)
    end
  end

  describe 'validations' do
    context 'coordinate validations' do
      it 'validates longitude is within -180 to 180' do
        service = described_class.new(valid_params.merge(min_lon: -181))
        
        expect(service).not_to be_valid
        expect(service.errors[:min_lon]).to include('is not included in the list')
      end

      it 'validates latitude is within -90 to 90' do
        service = described_class.new(valid_params.merge(max_lat: 91))
        
        expect(service).not_to be_valid
        expect(service.errors[:max_lat]).to include('is not included in the list')
      end

      it 'validates hex_size is positive' do
        service = described_class.new(valid_params.merge(hex_size: -100))
        
        expect(service).not_to be_valid
        expect(service.errors[:hex_size]).to include('must be greater than 0')
      end
    end

    context 'bounding box order validation' do
      it 'validates min_lon < max_lon' do
        service = described_class.new(valid_params.merge(min_lon: -73.8, max_lon: -73.9))
        
        expect(service).not_to be_valid
        expect(service.errors[:base]).to include('min_lon must be less than max_lon')
      end

      it 'validates min_lat < max_lat' do
        service = described_class.new(valid_params.merge(min_lat: 40.9, max_lat: 40.7))
        
        expect(service).not_to be_valid
        expect(service.errors[:base]).to include('min_lat must be less than max_lat')
      end
    end

    context 'area size validation' do
      let(:large_area_params) do
        {
          min_lon: -180,
          min_lat: -89,
          max_lon: 180,
          max_lat: 89
        }
      end

      it 'validates area is not too large' do
        service = described_class.new(large_area_params)
        
        expect(service).not_to be_valid
        expect(service.errors[:base].first).to include('Area too large')
      end

      it 'allows reasonable area sizes' do
        service = described_class.new(valid_params)
        
        expect(service).to be_valid
      end
    end
  end

  describe '#area_km2' do
    it 'calculates area correctly for small regions' do
      service = described_class.new(valid_params)
      
      # Expected area for NYC region: 0.1 degree lon × 0.1 degree lat ≈ 93 km²
      expect(service.area_km2).to be_within(5).of(93)
    end

    it 'handles polar regions differently due to longitude compression' do
      polar_params = {
        min_lon: -1,
        min_lat: 85,
        max_lon: 1,
        max_lat: 87
      }
      service = described_class.new(polar_params)
      
      # At high latitudes, longitude compression is significant, but 2×2 degrees still covers considerable area
      expect(service.area_km2).to be_within(500).of(3400)
    end
  end

  describe '#crosses_dateline?' do
    it 'returns true when crossing the international date line' do
      dateline_params = {
        min_lon: 179,
        min_lat: 0,
        max_lon: -179,
        max_lat: 1
      }
      service = described_class.new(dateline_params)
      
      expect(service.crosses_dateline?).to be true
    end

    it 'returns false for normal longitude ranges' do
      service = described_class.new(valid_params)
      
      expect(service.crosses_dateline?).to be false
    end
  end

  describe '#in_polar_region?' do
    it 'returns true for high northern latitudes' do
      polar_params = valid_params.merge(min_lat: 86, max_lat: 87)
      service = described_class.new(polar_params)
      
      expect(service.in_polar_region?).to be true
    end

    it 'returns true for high southern latitudes' do
      polar_params = valid_params.merge(min_lat: -87, max_lat: -86)
      service = described_class.new(polar_params)
      
      expect(service.in_polar_region?).to be true
    end

    it 'returns false for mid-latitude regions' do
      service = described_class.new(valid_params)
      
      expect(service.in_polar_region?).to be false
    end
  end

  describe '#estimated_hexagon_count' do
    it 'estimates hexagon count based on area and hex size' do
      service = described_class.new(valid_params)
      
      # For a ~93 km² area with 500m hexagons (0.65 km² each)
      # Should estimate around 144 hexagons
      expect(service.estimated_hexagon_count).to be_within(10).of(144)
    end

    it 'adjusts estimate based on hex size' do
      large_hex_service = described_class.new(valid_params.merge(hex_size: 1000))
      small_hex_service = described_class.new(valid_params.merge(hex_size: 250))
      
      expect(small_hex_service.estimated_hexagon_count).to be > large_hex_service.estimated_hexagon_count
    end
  end

  describe '#call' do
    context 'with valid parameters' do
      let(:mock_sql_result) do
        [
          {
            'id' => '1',
            'geojson' => '{"type":"Polygon","coordinates":[[[-74.0,40.7],[-73.99,40.7],[-73.99,40.71],[-74.0,40.71],[-74.0,40.7]]]}',
            'hex_i' => '0',
            'hex_j' => '0'
          },
          {
            'id' => '2',
            'geojson' => '{"type":"Polygon","coordinates":[[[-73.99,40.7],[-73.98,40.7],[-73.98,40.71],[-73.99,40.71],[-73.99,40.7]]]}',
            'hex_i' => '1',
            'hex_j' => '0'
          }
        ]
      end

      before do
        allow_any_instance_of(described_class).to receive(:execute_sql).and_return(mock_sql_result)
      end

      it 'returns a proper GeoJSON FeatureCollection' do
        service = described_class.new(valid_params)
        result = service.call
        
        expect(result[:type]).to eq('FeatureCollection')
        expect(result[:features]).to be_an(Array)
        expect(result[:features].length).to eq(2)
        expect(result[:metadata]).to be_a(Hash)
      end

      it 'includes correct feature properties' do
        service = described_class.new(valid_params)
        result = service.call
        
        feature = result[:features].first
        expect(feature[:type]).to eq('Feature')
        expect(feature[:id]).to eq('1')
        expect(feature[:geometry]).to be_a(Hash)
        expect(feature[:properties]).to include(
          hex_id: '1',
          hex_i: '0',
          hex_j: '0',
          hex_size: 500
        )
      end

      it 'includes metadata about the generation' do
        service = described_class.new(valid_params)
        result = service.call
        
        metadata = result[:metadata]
        expect(metadata).to include(
          bbox: [-74.0, 40.7, -73.9, 40.8],
          area_km2: be_a(Numeric),
          hex_size_m: 500,
          count: 2,
          estimated_count: be_a(Integer)
        )
      end
    end

    context 'with invalid coordinates' do
      it 'raises InvalidCoordinatesError for invalid coordinates' do
        # Use coordinates that are invalid but don't create a huge area
        invalid_service = described_class.new(valid_params.merge(min_lon: 181, max_lon: 182))
        
        expect { invalid_service.call }.to raise_error(Maps::HexagonGrid::InvalidCoordinatesError)
      end

      it 'raises InvalidCoordinatesError for reversed coordinates' do
        invalid_service = described_class.new(valid_params.merge(min_lon: -73.8, max_lon: -74.1))
        
        expect { invalid_service.call }.to raise_error(Maps::HexagonGrid::InvalidCoordinatesError)
      end
    end

    context 'with too large area' do
      let(:large_area_params) do
        {
          min_lon: -180,
          min_lat: -89,
          max_lon: 180,
          max_lat: 89
        }
      end

      it 'raises BoundingBoxTooLargeError' do
        service = described_class.new(large_area_params)
        
        expect { service.call }.to raise_error(Maps::HexagonGrid::BoundingBoxTooLargeError)
      end
    end

    context 'with database errors' do
      before do
        allow_any_instance_of(described_class).to receive(:execute_sql)
          .and_raise(ActiveRecord::StatementInvalid.new('PostGIS error'))
      end

      it 'raises PostGISError when SQL execution fails' do
        service = described_class.new(valid_params)
        
        expect { service.call }.to raise_error(Maps::HexagonGrid::PostGISError)
      end
    end
  end

  describe 'edge cases' do
    context 'with very small areas' do
      let(:small_area_params) do
        {
          min_lon: -74.0,
          min_lat: 40.7,
          max_lon: -73.999,
          max_lat: 40.701
        }
      end

      it 'handles very small bounding boxes' do
        service = described_class.new(small_area_params)
        
        expect(service).to be_valid
        expect(service.area_km2).to be < 1
      end
    end

    context 'with equatorial regions' do
      let(:equatorial_params) do
        {
          min_lon: 0,
          min_lat: -1,
          max_lon: 1,
          max_lat: 1
        }
      end

      it 'calculates area correctly near the equator' do
        service = described_class.new(equatorial_params)
        
        # Near equator, longitude compression is minimal
        # 1 degree x 2 degrees should be roughly 111 x 222 km
        expect(service.area_km2).to be_within(1000).of(24_642)
      end
    end

    context 'with custom hex sizes' do
      it 'uses custom hex size in calculations' do
        large_hex_service = described_class.new(valid_params.merge(hex_size: 2000))
        small_hex_service = described_class.new(valid_params.merge(hex_size: 100))
        
        expect(large_hex_service.estimated_hexagon_count).to be < small_hex_service.estimated_hexagon_count
      end
    end
  end

  describe 'SQL generation' do
    it 'generates proper SQL with parameters' do
      service = described_class.new(valid_params.merge(hex_size: 750))
      sql = service.send(:build_hexagon_sql)
      
      expect(sql).to include('ST_MakeEnvelope(-74.0, 40.7, -73.9, 40.8, 4326)')
      expect(sql).to include('ST_HexagonGrid(750')
      expect(sql).to include('LIMIT 5000')
    end

    it 'includes hex grid coordinates (i, j) in output' do
      service = described_class.new(valid_params)
      sql = service.send(:build_hexagon_sql)
      
      expect(sql).to include('hex_i')
      expect(sql).to include('hex_j')
      expect(sql).to include('(ST_HexagonGrid(')
    end
  end

  describe 'logging' do
    let(:mock_result) do
      [
        {
          'id' => '1',
          'geojson' => '{"type":"Polygon","coordinates":[[[-74.0,40.7]]]}',
          'hex_i' => '0',
          'hex_j' => '0'
        }
      ]
    end

    before do
      allow_any_instance_of(described_class).to receive(:execute_sql).and_return(mock_result)
      allow(Rails.logger).to receive(:debug)
      allow(Rails.logger).to receive(:info)
    end

    it 'logs debug information during generation' do
      service = described_class.new(valid_params)
      service.call
      
      expect(Rails.logger).to have_received(:debug).with(/Generating hexagons for bbox/)
      expect(Rails.logger).to have_received(:debug).with(/Estimated hexagon count/)
    end

    it 'logs generation results' do
      service = described_class.new(valid_params)
      service.call
      
      expect(Rails.logger).to have_received(:info).with(/Generated 1 hexagons for area/)
    end
  end
end
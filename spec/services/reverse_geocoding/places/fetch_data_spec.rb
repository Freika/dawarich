# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ReverseGeocoding::Places::FetchData do
  subject(:service) { described_class.new(place.id) }

  let(:place) { create(:place) }
  let(:mock_geocoded_place) do
    double(
      data: {
        'geometry' => {
          'coordinates' => [13.0948638, 54.2905245]
        },
        'properties' => {
          'osm_id' => 12345,
          'name' => 'Test Place',
          'osm_value' => 'restaurant',
          'city' => 'Berlin',
          'country' => 'Germany',
          'postcode' => '10115',
          'street' => 'Test Street',
          'housenumber' => '1'
        }
      }
    )
  end

  describe '#call' do
    context 'when reverse geocoding is enabled' do
      before do
        allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(true)
        allow(Geocoder).to receive(:search).and_return([mock_geocoded_place])
      end

      it 'fetches geocoded places' do
        service.call

        expect(Geocoder).to have_received(:search).with(
          [place.lat, place.lon],
          limit: 10,
          distance_sort: true,
          radius: 1,
          units: :km
        )
      end

      it 'updates the original place with geocoded data' do
        expect { service.call }.to change { place.reload.name }
          .and change { place.reload.city }.to('Berlin')
          .and change { place.reload.country }.to('Germany')
      end

      it 'sets reverse_geocoded_at timestamp' do
        expect { service.call }.to change { place.reload.reverse_geocoded_at }
          .from(nil)

        expect(place.reload.reverse_geocoded_at).to be_present
      end

      it 'sets the source to photon' do
        expect { service.call }.to change { place.reload.source }
          .to('photon')
      end

      context 'with multiple geocoded places' do
        let(:second_mock_place) do
          double(
            data: {
              'geometry' => {
                'coordinates' => [13.1, 54.3]
              },
              'properties' => {
                'osm_id' => 67890,
                'name' => 'Second Place',
                'osm_value' => 'cafe',
                'city' => 'Hamburg',
                'country' => 'Germany'
              }
            }
          )
        end

        before do
          allow(Geocoder).to receive(:search).and_return([mock_geocoded_place, second_mock_place])
        end

        it 'creates new places for additional geocoded results' do
          # Force place creation before counting
          place # This triggers the let(:place) lazy loading
          initial_count = Place.count
          service.call
          final_count = Place.count

          expect(final_count - initial_count).to eq(1)
        end

        it 'updates the original place and creates others' do
          service.call

          created_place = Place.where.not(id: place.id).first
          expect(created_place.name).to include('Second Place')
          expect(created_place.city).to eq('Hamburg')
        end
      end

      context 'with existing places in database' do
        let!(:existing_place) { create(:place, :with_geodata) }

        before do
          # Mock geocoded place with same OSM ID as existing place
          existing_osm_id = existing_place.geodata.dig('properties', 'osm_id')
          mock_with_existing_osm = double(
            data: {
              'geometry' => { 'coordinates' => [13.0948638, 54.2905245] },
              'properties' => {
                'osm_id' => existing_osm_id,
                'name' => 'Updated Name',
                'osm_value' => 'restaurant',
                'city' => 'Updated City',
                'country' => 'Updated Country'
              }
            }
          )

          allow(Geocoder).to receive(:search).and_return([mock_geocoded_place, mock_with_existing_osm])
        end

        it 'updates existing places instead of creating duplicates' do
          place # Force place creation
          expect { service.call }.not_to change { Place.count }
        end

        it 'updates the existing place attributes' do
          service.call

          existing_place.reload
          expect(existing_place.name).to include('Updated Name')
          expect(existing_place.city).to eq('Updated City')
        end
      end

      context 'when first geocoded place is nil' do
        before do
          allow(Geocoder).to receive(:search).and_return([nil, mock_geocoded_place])
        end

        it 'does not update the original place' do
          place # Force place creation
          expect { service.call }.not_to change { place.reload.updated_at }
        end

        it 'still processes other places' do
          place # Force place creation
          expect { service.call }.to change { Place.count }.by(1)
        end
      end

      context 'when no additional places are returned' do
        before do
          allow(Geocoder).to receive(:search).and_return([mock_geocoded_place])
        end

        it 'only updates the original place' do
          place # Force place creation
          expect { service.call }.not_to change { Place.count }
        end

        it 'returns early when osm_ids is empty' do
          # This tests the early return when osm_ids.empty?
          service.call

          expect(Geocoder).to have_received(:search).once
        end
      end
    end

    context 'when reverse geocoding is disabled' do
      before do
        allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(false)
        allow(Rails.logger).to receive(:warn)
      end

      it 'logs a warning and returns early' do
        service.call

        expect(Rails.logger).to have_received(:warn).with('Reverse geocoding is not enabled')
      end

      it 'does not call Geocoder' do
        allow(Geocoder).to receive(:search)
        service.call

        expect(Geocoder).not_to have_received(:search)
      end

      it 'does not update the place' do
        expect { service.call }.not_to change { place.reload.updated_at }
      end
    end
  end

  describe 'private methods' do
    before do
      allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(true)
    end

    describe '#place_name' do
      it 'builds place name from properties' do
        data = {
          'properties' => {
            'name' => 'Test Restaurant',
            'osm_value' => 'restaurant',
            'postcode' => '10115',
            'street' => 'Main Street',
            'housenumber' => '42'
          }
        }

        result = service.send(:place_name, data)
        expect(result).to eq('Test Restaurant (Restaurant)')
      end

      it 'uses address when name is missing' do
        data = {
          'properties' => {
            'osm_value' => 'cafe',
            'postcode' => '10115',
            'street' => 'Oak Street',
            'housenumber' => '123'
          }
        }

        result = service.send(:place_name, data)
        expect(result).to eq('10115 Oak Street 123 (Cafe)')
      end

      it 'handles missing housenumber' do
        data = {
          'properties' => {
            'name' => 'Test Place',
            'osm_value' => 'shop',
            'postcode' => '10115',
            'street' => 'Pine Street'
          }
        }

        result = service.send(:place_name, data)
        expect(result).to eq('Test Place (Shop)')
      end

      it 'formats osm_value correctly' do
        data = {
          'properties' => {
            'name' => 'Test',
            'osm_value' => 'fast_food_restaurant'
          }
        }

        result = service.send(:place_name, data)
        expect(result).to eq('Test (Fast food restaurant)')
      end
    end

    describe '#extract_osm_ids' do
      it 'extracts OSM IDs from places' do
        places = [
          double(data: { 'properties' => { 'osm_id' => 123 } }),
          double(data: { 'properties' => { 'osm_id' => 456 } })
        ]

        result = service.send(:extract_osm_ids, places)
        expect(result).to eq(['123', '456'])
      end
    end

    describe '#build_point_coordinates' do
      it 'builds POINT geometry string' do
        coordinates = [13.0948638, 54.2905245]
        result = service.send(:build_point_coordinates, coordinates)
        expect(result).to eq('POINT(13.0948638 54.2905245)')
      end
    end

    describe '#find_existing_places' do
      let!(:existing_place1) { create(:place, :with_geodata) }
      let!(:existing_place2) do
        create(:place, geodata: {
          'properties' => { 'osm_id' => 999 }
        })
      end

      it 'finds existing places by OSM IDs' do
        osm_id1 = existing_place1.geodata.dig('properties', 'osm_id').to_s
        osm_ids = [osm_id1, '999']

        result = service.send(:find_existing_places, osm_ids)

        expect(result.keys).to contain_exactly(osm_id1, '999')
        expect(result[osm_id1]).to eq(existing_place1)
        expect(result['999']).to eq(existing_place2)
      end

      it 'returns empty hash when no matches found' do
        result = service.send(:find_existing_places, ['nonexistent'])
        expect(result).to eq({})
      end
    end

    describe '#find_place' do
      let(:existing_places) { { '123' => create(:place) } }
      let(:place_data) do
        {
          'properties' => { 'osm_id' => 123 },
          'geometry' => { 'coordinates' => [13.1, 54.3] }
        }
      end

      context 'when place exists' do
        it 'returns existing place' do
          result = service.send(:find_place, place_data, existing_places)
          expect(result).to eq(existing_places['123'])
        end
      end

      context 'when place does not exist' do
        let(:place_data) do
          {
            'properties' => { 'osm_id' => 999 },
            'geometry' => { 'coordinates' => [13.1, 54.3] }
          }
        end

        it 'creates new place with coordinates' do
          result = service.send(:find_place, place_data, existing_places)

          expect(result).to be_a(Place)
          expect(result.latitude).to eq(54.3)
          expect(result.longitude).to eq(13.1)
          expect(result.lonlat.to_s).to eq('POINT (13.1 54.3)')
        end
      end
    end

    describe '#populate_place_attributes' do
      let(:test_place) { Place.new }
      let(:data) do
        {
          'properties' => {
            'name' => 'Test Place',
            'osm_value' => 'restaurant',
            'city' => 'Berlin',
            'country' => 'Germany'
          },
          'geometry' => { 'coordinates' => [13.1, 54.3] }
        }
      end

      it 'populates all place attributes' do
        place # Ensure place exists
        service.send(:populate_place_attributes, test_place, data)

        expect(test_place.name).to include('Test Place')
        expect(test_place.city).to eq('Berlin')
        expect(test_place.country).to eq('Germany')
        expect(test_place.geodata).to eq(data)
        expect(test_place.source).to eq('photon')
      end

      it 'sets lonlat when nil' do
        place # Ensure place exists
        service.send(:populate_place_attributes, test_place, data)
        expect(test_place.lonlat.to_s).to eq('POINT (13.1 54.3)')
      end

      it 'does not override existing lonlat' do
        place # Ensure place exists
        test_place.lonlat = 'POINT(10.0 50.0)'
        service.send(:populate_place_attributes, test_place, data)
        expect(test_place.lonlat.to_s).to eq('POINT (10.0 50.0)')
      end
    end

    describe '#prepare_places_for_bulk_operations' do
      let(:new_place_data) do
        double(
          data: {
            'properties' => { 'osm_id' => 999 },
            'geometry' => { 'coordinates' => [13.1, 54.3] }
          }
        )
      end
      let(:existing_place) { create(:place, :with_geodata) }
      let(:existing_place_data) do
        double(
          data: {
            'properties' => { 'osm_id' => existing_place.geodata.dig('properties', 'osm_id') },
            'geometry' => { 'coordinates' => [13.2, 54.4] }
          }
        )
      end

      it 'separates places into create and update arrays' do
        existing_places = { existing_place.geodata.dig('properties', 'osm_id').to_s => existing_place }
        places = [new_place_data, existing_place_data]

        places_to_create, places_to_update = service.send(:prepare_places_for_bulk_operations, places, existing_places)

        expect(places_to_create.length).to eq(1)
        expect(places_to_update.length).to eq(1)
        expect(places_to_update.first).to eq(existing_place)
        expect(places_to_create.first).to be_a(Place)
        expect(places_to_create.first.persisted?).to be(false)
      end
    end

    describe '#save_places' do
      it 'saves new places when places_to_create is present' do
        place # Ensure place exists
        new_place = build(:place)
        places_to_create = [new_place]
        places_to_update = []

        expect { service.send(:save_places, places_to_create, places_to_update) }
          .to change { Place.count }.by(1)
      end

      it 'saves updated places when places_to_update is present' do
        existing_place = create(:place, name: 'Old Name')
        existing_place.name = 'New Name'
        places_to_create = []
        places_to_update = [existing_place]

        service.send(:save_places, places_to_create, places_to_update)

        expect(existing_place.reload.name).to eq('New Name')
      end

      it 'handles empty arrays gracefully' do
        expect { service.send(:save_places, [], []) }.not_to raise_error
      end
    end
  end

  describe 'edge cases and error scenarios' do
    before do
      allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(true)
    end

    context 'when Geocoder returns empty results' do
      before do
        allow(Geocoder).to receive(:search).and_return([])
      end

      it 'handles empty geocoder results gracefully' do
        expect { service.call }.not_to raise_error
      end

      it 'does not update the place' do
        expect { service.call }.not_to change { place.reload.updated_at }
      end
    end

    context 'when Geocoder raises an exception' do
      before do
        allow(Geocoder).to receive(:search).and_raise(StandardError.new('Geocoding failed'))
      end

      it 'allows the exception to bubble up' do
        expect { service.call }.to raise_error(StandardError, 'Geocoding failed')
      end
    end

    context 'when place data is malformed' do
      let(:malformed_place) do
        double(
          data: {
            'geometry' => {
              'coordinates' => ['invalid', 'coordinates']
            },
            'properties' => {
              'osm_id' => nil
            }
          }
        )
      end

      before do
        allow(Geocoder).to receive(:search).and_return([mock_geocoded_place, malformed_place])
      end

      it 'handles malformed data gracefully' do
        # With bulk operations using insert_all, validation errors are bypassed
        # Malformed data will be inserted but may cause issues at the database level
        place # Force place creation
        expect { service.call }.not_to raise_error
      end
    end

    context 'when using bulk operations' do
      let(:second_geocoded_place) do
        double(
          data: {
            'geometry' => { 'coordinates' => [14.0, 55.0] },
            'properties' => {
              'osm_id' => 99999,
              'name' => 'Another Place',
              'osm_value' => 'shop'
            }
          }
        )
      end

      it 'uses bulk operations for performance' do
        place # Force place creation first

        allow(Geocoder).to receive(:search).and_return([mock_geocoded_place, second_geocoded_place])
        # With insert_all, we expect the operation to succeed even with potential validation issues
        # since bulk operations bypass ActiveRecord validations for performance

        expect { service.call }.to change { Place.count }.by(1)
      end
    end

    context 'when database constraint violations occur' do
      let(:duplicate_place) { create(:place, :with_geodata) }
      let(:duplicate_data) do
        double(
          data: {
            'geometry' => { 'coordinates' => [13.1, 54.3] },
            'properties' => {
              'osm_id' => duplicate_place.geodata.dig('properties', 'osm_id'),
              'name' => 'Duplicate'
            }
          }
        )
      end

      before do
        allow(Geocoder).to receive(:search).and_return([mock_geocoded_place, duplicate_data])
        # Simulate the place not being found in existing_places due to race condition
        allow(service).to receive(:find_existing_places).and_return({})
      end

      it 'handles potential race conditions gracefully' do
        # The service should handle cases where a place might be created
        # between the existence check and the actual creation
        expect { service.call }.not_to raise_error
      end
    end

    context 'when place_id does not exist' do
      subject(:service) { described_class.new(999999) }

      it 'raises ActiveRecord::RecordNotFound' do
        expect { service }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    context 'with missing properties in geocoded data' do
      let(:minimal_place) do
        double(
          data: {
            'geometry' => {
              'coordinates' => [13.0, 54.0]
            },
            'properties' => {
              'osm_id' => 99999
              # Missing name, city, country, etc.
            }
          }
        )
      end

      before do
        allow(Geocoder).to receive(:search).and_return([mock_geocoded_place, minimal_place])
      end

      it 'handles missing properties gracefully' do
        expect { service.call }.not_to raise_error
      end

      it 'creates place with available data' do
        place # Force place creation
        expect { service.call }.to change { Place.count }.by(1)

        created_place = Place.where.not(id: place.id).first
        expect(created_place.latitude).to eq(54.0)
        expect(created_place.longitude).to eq(13.0)
      end
    end

    context 'when lonlat is already present on existing place' do
      let!(:existing_place) { create(:place, :with_geodata, lonlat: 'POINT(10.0 50.0)') }
      let(:existing_data) do
        double(
          data: {
            'geometry' => { 'coordinates' => [15.0, 55.0] },
            'properties' => {
              'osm_id' => existing_place.geodata.dig('properties', 'osm_id'),
              'name' => 'Updated Name'
            }
          }
        )
      end

      before do
        allow(Geocoder).to receive(:search).and_return([mock_geocoded_place, existing_data])
      end

      it 'does not override existing lonlat' do
        service.call

        existing_place.reload
        expect(existing_place.lonlat.to_s).to eq('POINT (10.0 50.0)')
      end
    end
  end
end

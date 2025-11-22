# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::ImportData::Places, type: :service do
  let(:user) { create(:user) }
  let(:places_data) do
    [
      {
        'name' => 'Home',
        'latitude' => '40.7128',
        'longitude' => '-74.0060',
        'source' => 'manual',
        'geodata' => { 'address' => '123 Main St' },
        'created_at' => '2024-01-01T00:00:00Z',
        'updated_at' => '2024-01-01T00:00:00Z'
      },
      {
        'name' => 'Office',
        'latitude' => '40.7589',
        'longitude' => '-73.9851',
        'source' => 'photon',
        'geodata' => { 'properties' => { 'name' => 'Office Building' } },
        'created_at' => '2024-01-02T00:00:00Z',
        'updated_at' => '2024-01-02T00:00:00Z'
      }
    ]
  end
  let(:service) { described_class.new(user, places_data) }

  describe '#call' do
    context 'with valid places data' do
      it 'creates new places' do
        expect { service.call }.to change { Place.count }.by(2)
      end

      it 'creates places with correct attributes' do
        service.call

        home_place = Place.find_by(name: 'Home')
        expect(home_place).to have_attributes(
          name: 'Home',
          source: 'manual'
        )
        expect(home_place.lat).to be_within(0.0001).of(40.7128)
        expect(home_place.lon).to be_within(0.0001).of(-74.0060)
        expect(home_place.geodata).to eq('address' => '123 Main St')

        office_place = Place.find_by(name: 'Office')
        expect(office_place).to have_attributes(
          name: 'Office',
          source: 'photon'
        )
        expect(office_place.lat).to be_within(0.0001).of(40.7589)
        expect(office_place.lon).to be_within(0.0001).of(-73.9851)
        expect(office_place.geodata).to eq('properties' => { 'name' => 'Office Building' })
      end

      it 'returns the number of places created' do
        result = service.call
        expect(result).to eq(2)
      end
    end

    context 'with duplicate places (same name)' do
      before do
        # Create an existing place with same name but different coordinates
        create(:place, name: 'Home',
               latitude: 41.0000, longitude: -75.0000,
               lonlat: 'POINT(-75.0000 41.0000)')
      end

      it 'creates the place since coordinates are different' do
        expect { service.call }.to change { Place.count }.by(2)
      end

      it 'creates both places with different coordinates' do
        service.call
        home_places = Place.where(name: 'Home')
        expect(home_places.count).to eq(2)

        imported_home = home_places.find_by(latitude: 40.7128, longitude: -74.0060)
        expect(imported_home).to be_present
      end
    end

    context 'with exact duplicate places (same name and coordinates)' do
      before do
        # Create an existing place with exact same name and coordinates
        create(:place, name: 'Home',
               latitude: 40.7128, longitude: -74.0060,
               lonlat: 'POINT(-74.0060 40.7128)')
      end

      it 'skips exact duplicate places' do
        expect { service.call }.to change { Place.count }.by(1)
      end

      it 'returns only the count of newly created places' do
        result = service.call
        expect(result).to eq(1)
      end
    end

    context 'with duplicate places (same coordinates)' do
      before do
        # Create an existing place with same coordinates but different name
        create(:place, name: 'Different Name',
               latitude: 40.7128, longitude: -74.0060,
               lonlat: 'POINT(-74.0060 40.7128)')
      end

      it 'creates the place since name is different' do
        expect { service.call }.to change { Place.global.count }.by(2)
      end

      it 'creates both places with different names' do
        service.call
        places_at_location = Place.where(latitude: 40.7128, longitude: -74.0060, user_id: nil)
        expect(places_at_location.count).to eq(2)
        expect(places_at_location.pluck(:name)).to contain_exactly('Home', 'Different Name')
      end
    end

    context 'with places having same name but different coordinates' do
      before do
        create(:place, name: 'Different Place',
               latitude: 41.0000, longitude: -75.0000,
               lonlat: 'POINT(-75.0000 41.0000)')
      end

      it 'creates both places since coordinates and names differ' do
        expect { service.call }.to change { Place.count }.by(2)
      end
    end

    context 'with invalid place data' do
      let(:places_data) do
        [
          { 'name' => 'Valid Place', 'latitude' => '40.7128', 'longitude' => '-74.0060' },
          'invalid_data',
          { 'name' => 'Another Valid Place', 'latitude' => '40.7589', 'longitude' => '-73.9851' }
        ]
      end

      it 'skips invalid entries and imports valid ones' do
        expect { service.call }.to change { Place.count }.by(2)
      end

      it 'returns the count of valid places created' do
        result = service.call
        expect(result).to eq(2)
      end
    end

    context 'with missing required fields' do
      let(:places_data) do
        [
          { 'name' => 'Valid Place', 'latitude' => '40.7128', 'longitude' => '-74.0060' },
          { 'latitude' => '40.7589', 'longitude' => '-73.9851' }, # missing name
          { 'name' => 'Invalid Place', 'longitude' => '-73.9851' }, # missing latitude
          { 'name' => 'Another Invalid Place', 'latitude' => '40.7589' } # missing longitude
        ]
      end

      it 'only creates places with all required fields' do
        expect { service.call }.to change { Place.count }.by(1)
      end
    end

    context 'with nil places data' do
      let(:places_data) { nil }

      it 'does not create any places' do
        expect { service.call }.not_to change { Place.count }
      end

      it 'returns 0' do
        result = service.call
        expect(result).to eq(0)
      end
    end

    context 'with non-array places data' do
      let(:places_data) { 'invalid_data' }

      it 'does not create any places' do
        expect { service.call }.not_to change { Place.count }
      end

      it 'returns 0' do
        result = service.call
        expect(result).to eq(0)
      end
    end

    context 'with empty places data' do
      let(:places_data) { [] }

      it 'does not create any places' do
        expect { service.call }.not_to change { Place.count }
      end

      it 'returns 0' do
        result = service.call
        expect(result).to eq(0)
      end
    end
  end
end

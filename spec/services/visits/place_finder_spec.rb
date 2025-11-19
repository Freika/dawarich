# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Visits::PlaceFinder do
  let(:user) { create(:user) }
  let(:latitude) { 40.7128 }
  let(:longitude) { -74.0060 }

  subject { described_class.new(user) }

  describe '#find_or_create_place' do
    let(:visit_data) do
      {
        center_lat: latitude,
        center_lon: longitude,
        suggested_name: 'Test Place',
        points: []
      }
    end

    context 'when an existing place is found' do
      let!(:existing_place) { create(:place, user: user, latitude: latitude, longitude: longitude) }

      it 'returns the existing place as main_place' do
        result = subject.find_or_create_place(visit_data)

        expect(result).to be_a(Hash)
        expect(result[:main_place]).to eq(existing_place)
      end

      it 'includes suggested places in the result' do
        result = subject.find_or_create_place(visit_data)

        expect(result[:suggested_places]).to respond_to(:each)
        expect(result[:suggested_places]).to include(existing_place)
      end

      it 'finds an existing place by name within search radius' do
        similar_named_place = create(:place,
                                     user: user,
                                     name: 'Test Place',
                                     latitude: latitude + 0.0001,
                                     longitude: longitude + 0.0001)

        allow(subject).to receive(:find_existing_place).and_return(similar_named_place)

        modified_visit_data = visit_data.merge(
          center_lat: latitude + 0.0002,
          center_lon: longitude + 0.0002
        )

        result = subject.find_or_create_place(modified_visit_data)

        expect(result[:main_place]).to eq(similar_named_place)
      end
    end

    context 'with places from points data' do
      let(:point_with_geodata) do
        build_stubbed(:point,
                      lonlat: "POINT(#{longitude} #{latitude})",
                      geodata: {
                        'properties' => {
                          'name' => 'POI from Point',
                          'city' => 'New York',
                          'country' => 'USA'
                        }
                      })
      end

      let(:visit_data_with_points) do
        visit_data.merge(points: [point_with_geodata])
      end

      before do
        allow(Geocoder).to receive(:search).and_return([])
        allow(subject).to receive(:reverse_geocoded_places).and_return([])
      end

      it 'extracts and creates places from point geodata' do
        allow(subject).to receive(:create_place_from_point).and_call_original

        expect do
          result = subject.find_or_create_place(visit_data_with_points)
          expect(result[:main_place].name).to include('POI from Point')
        end.to change(Place, :count).by(1)

        expect(subject).to have_received(:create_place_from_point)
      end
    end

    context 'when no existing place is found' do
      let(:geocoder_result) do
        double(
          data: {
            'properties' => {
              'name' => 'Test Location',
              'street' => 'Test Street',
              'city' => 'Test City',
              'country' => 'Test Country'
            }
          },
          latitude: latitude,
          longitude: longitude
        )
      end

      let(:other_geocoder_result) do
        double(
          data: {
            'properties' => {
              'name' => 'Other Location',
              'street' => 'Other Street',
              'city' => 'Test City',
              'country' => 'Test Country'
            }
          },
          latitude: latitude + 0.001,
          longitude: longitude + 0.001
        )
      end

      before do
        allow(Geocoder).to receive(:search).and_return([geocoder_result, other_geocoder_result])
      end

      it 'creates a new place with geocoded data' do
        expect do
          result = subject.find_or_create_place(visit_data)
          expect(result[:main_place].name).to include('Test Location')
        end.to change(Place, :count).by(2)

        place = Place.find_by_name('Test Location, Test Street, Test City')

        expect(place.city).to eq('Test City')
        expect(place.country).to eq('Test Country')
        expect(place.source).to eq('photon')
      end

      it 'returns both main place and suggested places' do
        result = subject.find_or_create_place(visit_data)

        expect(result[:main_place].name).to include('Test Location')
        expect(result[:suggested_places].length).to eq(2)

        expect(result[:suggested_places].map(&:name)).to include(
          'Test Location, Test Street, Test City',
          'Other Location, Other Street, Test City'
        )
      end

      context 'when geocoding returns no results' do
        before do
          allow(Geocoder).to receive(:search).and_return([])
        end

        it 'creates a place with the suggested name' do
          expect do
            result = subject.find_or_create_place(visit_data)
            expect(result[:main_place].name).to eq('Test Place')
          end.to change(Place, :count).by(1)

          place = Place.last
          expect(place.name).to eq('Test Place')
          expect(place.source).to eq('manual')
        end

        it 'returns the created place as both main and the only suggested place' do
          result = subject.find_or_create_place(visit_data)

          expect(result[:main_place].name).to eq('Test Place')
          expect(result[:suggested_places]).to eq([result[:main_place]])
        end

        it 'falls back to default name when suggested name is missing' do
          visit_data_without_name = visit_data.merge(suggested_name: nil)

          result = subject.find_or_create_place(visit_data_without_name)

          expect(result[:main_place].name).to eq(Place::DEFAULT_NAME)
        end
      end
    end

    context 'with multiple potential places' do
      let!(:place1) { create(:place, user: user, name: 'Place 1', latitude: latitude, longitude: longitude) }
      let!(:place2) { create(:place, user: user, name: 'Place 2', latitude: latitude + 0.0005, longitude: longitude + 0.0005) }
      let!(:place3) { create(:place, user: user, name: 'Place 3', latitude: latitude + 0.001, longitude: longitude + 0.001) }

      it 'selects the closest place as main_place' do
        result = subject.find_or_create_place(visit_data)

        expect(result[:main_place]).to eq(place1)
      end

      it 'includes nearby places as suggested_places' do
        result = subject.find_or_create_place(visit_data)

        expect(result[:suggested_places]).to include(place1, place2)
        # place3 might be outside the search radius depending on the constants defined
      end

      it 'may include places with the same name' do
        dup_place = create(:place, user: user, name: 'Place 1', latitude: latitude + 0.0002, longitude: longitude + 0.0002)

        allow(subject).to receive(:place_name_exists?).and_return(false)

        result = subject.find_or_create_place(visit_data)

        names = result[:suggested_places].map(&:name)
        expect(names.count('Place 1')).to be >= 1
      end
    end

    context 'with API place creation failures' do
      let(:invalid_geocoder_result) do
        double(
          data: {
            'properties' => {
              # Missing required fields
            }
          },
          latitude: latitude,
          longitude: longitude
        )
      end

      before do
        allow(Geocoder).to receive(:search).and_return([invalid_geocoder_result])
      end

      it 'gracefully handles errors in place creation' do
        allow(subject).to receive(:create_place_from_api_result).and_call_original

        result = subject.find_or_create_place(visit_data)

        # Should create the default place
        expect(result[:main_place].name).to eq('Test Place')
        expect(result[:main_place].source).to eq('manual')
      end
    end
  end

  describe 'private methods' do
    context '#build_place_name' do
      it 'combines name components correctly' do
        properties = {
          'name' => 'Coffee Shop',
          'street' => 'Main St',
          'housenumber' => '123',
          'city' => 'New York'
        }

        name = subject.send(:build_place_name, properties)
        expect(name).to eq('Coffee Shop, Main St, 123, New York')
      end

      it 'removes duplicate components' do
        properties = {
          'name' => 'Coffee Shop',
          'street' => 'Coffee Shop', # Duplicate of name
          'city' => 'New York'
        }

        name = subject.send(:build_place_name, properties)
        expect(name).to eq('Coffee Shop, New York')
      end

      it 'returns default name when no components are available' do
        properties = { 'other' => 'irrelevant' }

        name = subject.send(:build_place_name, properties)
        expect(name).to eq(Place::DEFAULT_NAME)
      end
    end
  end
end

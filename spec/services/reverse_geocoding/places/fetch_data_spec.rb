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
          'osm_id' => 12_345,
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
        configure_instance_geocoding
        allow(Geocoder).to receive(:search).and_return([mock_geocoded_place])
      end

      it 'asks the geocoder for the nearest feature only' do
        service.call

        expect(Geocoder).to have_received(:search).with(
          [place.lat, place.lon],
          limit: 1,
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

      context 'when the place name is locked by the user' do
        let(:place) { create(:place, name: "Mum's house", name_locked_at: 1.day.ago) }

        it 'keeps the user-supplied name' do
          expect { service.call }.not_to(change { place.reload.name })
        end

        it 'still refreshes city and country' do
          expect { service.call }.to change { place.reload.city }.to('Berlin')
        end
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

      # Some providers (Nominatim) ignore the limit, so the service must cope
      # with extra results either way.
      context 'when the geocoder returns other nearby features too' do
        let(:second_mock_place) do
          double(
            data: {
              'geometry' => {
                'coordinates' => [13.1, 54.3]
              },
              'properties' => {
                'osm_id' => 67_890,
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

        it 'does not save them as places' do
          place

          expect { service.call }.not_to(change { Place.count })
        end

        it 'updates the place from the nearest feature' do
          service.call

          expect(place.reload.name).to include('Test Place')
          expect(place.city).to eq('Berlin')
        end

        context 'when one of them matches an existing place' do
          let!(:existing_place) do
            create(:place, user: place.user, name: 'Corner Cafe', city: 'Rostock',
                           geodata: { 'properties' => { 'osm_id' => 67_890 } })
          end

          it 'leaves that place unchanged' do
            expect { service.call }
              .not_to(change { existing_place.reload.slice(:name, :city, :source, :geodata, :updated_at) })
          end
        end
      end

      context 'when first geocoded place is nil' do
        before do
          allow(Geocoder).to receive(:search).and_return([nil, mock_geocoded_place])
        end

        it 'does not update the original place' do
          place # Force place creation
          expect { service.call }.not_to(change { place.reload.updated_at })
        end

        it 'does not create places from the other results' do
          place # Force place creation
          expect { service.call }.not_to(change { Place.count })
        end
      end
    end

    context 'when reverse geocoding is disabled' do
      before do
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
        expect { service.call }.not_to(change { place.reload.updated_at })
      end
    end
  end

  describe 'private methods' do
    before do
      configure_instance_geocoding
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

      it 'omits generic boolean osm values from place names' do
        data = {
          'properties' => {
            'name' => 'Gas Station',
            'osm_value' => 'yes',
            'postcode' => '10115',
            'street' => 'Main Street'
          }
        }

        result = service.send(:place_name, data)
        expect(result).to eq('Gas Station')
      end

      it 'falls back to the address when Photon returns a generic name' do
        data = {
          'properties' => {
            'name' => 'Yes',
            'osm_value' => 'yes',
            'postcode' => '10115',
            'street' => 'Main Street',
            'housenumber' => '42'
          }
        }

        result = service.send(:place_name, data)
        expect(result).to eq('10115 Main Street 42')
      end
    end

    describe '#build_point_coordinates' do
      it 'builds POINT geometry string' do
        coordinates = [13.0948638, 54.2905245]
        result = service.send(:build_point_coordinates, coordinates)
        expect(result).to eq('POINT(13.0948638 54.2905245)')
      end
    end
  end

  describe 'edge cases and error scenarios' do
    before do
      configure_instance_geocoding
    end

    context 'when Geocoder returns empty results' do
      before do
        allow(Geocoder).to receive(:search).and_return([])
      end

      it 'handles empty geocoder results gracefully' do
        expect { service.call }.not_to raise_error
      end

      it 'does not update the place' do
        expect { service.call }.not_to(change { place.reload.updated_at })
      end
    end

    context 'when Geocoder raises an exception' do
      before do
        allow(Geocoder).to receive(:search).and_raise(StandardError.new('Geocoding failed'))
        allow(ExceptionReporter).to receive(:call)
        allow(Rails.logger).to receive(:error)
      end

      it 'handles the exception gracefully and returns nil' do
        expect { service.call }.not_to raise_error
      end

      it 'logs the error' do
        service.call
        expect(Rails.logger).to have_received(:error).with(/Reverse geocoding error for place #{place.id}/)
      end

      it 'reports the exception' do
        service.call
        expect(ExceptionReporter).to have_received(:call)
      end
    end

    context 'when using Nominatim geocoder response format' do
      let(:nominatim_place) do
        double(
          data: {
            'place_id' => 123_456,
            'osm_type' => 'way',
            'osm_id' => 78_901,
            'lat' => '54.2905245',
            'lon' => '13.0948638',
            'type' => 'restaurant',
            'class' => 'amenity',
            'display_name' => 'Test Restaurant, Test Street 1, Berlin, Germany',
            'address' => {
              'restaurant' => 'Test Restaurant',
              'road' => 'Test Street',
              'house_number' => '1',
              'postcode' => '10115',
              'city' => 'Berlin',
              'country' => 'Germany'
            }
          }
        )
      end

      let(:second_nominatim_place) do
        double(
          data: {
            'osm_id' => 78_902,
            'lat' => '54.3',
            'lon' => '13.1',
            'type' => 'cafe',
            'class' => 'amenity',
            'display_name' => 'Nice Cafe, Oak Street, Hamburg, Germany',
            'address' => {
              'cafe' => 'Nice Cafe',
              'road' => 'Oak Street',
              'city' => 'Hamburg',
              'country' => 'Germany'
            }
          }
        )
      end

      before do
        configure_instance_geocoding(nominatim_api_host: 'nominatim.test.example.com')
        allow(Geocoder).to receive(:search).and_return([nominatim_place, second_nominatim_place])
      end

      it 'normalizes Nominatim data and updates the original place' do
        service.call

        place.reload
        expect(place.name).to include('Test Restaurant')
        expect(place.city).to eq('Berlin')
        expect(place.country).to eq('Germany')
      end

      it 'does not create places from the other Nominatim results' do
        place # Force creation
        expect { service.call }.not_to(change { Place.count })
      end

      it 'extracts coordinates from lat/lon fields' do
        service.call

        place.reload
        expect(place.lonlat.x).to be_within(0.001).of(13.0948638)
        expect(place.lonlat.y).to be_within(0.001).of(54.2905245)
      end

      it 'uses display_name first part when address type key is missing' do
        nominatim_without_type_key = double(
          data: {
            'osm_id' => 78_903,
            'lat' => '54.29',
            'lon' => '13.09',
            'type' => 'house',
            'display_name' => '123 Main Street, Berlin, Germany',
            'address' => {
              'road' => 'Main Street',
              'city' => 'Berlin',
              'country' => 'Germany'
            }
          }
        )

        allow(Geocoder).to receive(:search).and_return([nominatim_without_type_key])
        service.call

        place.reload
        expect(place.name).to include('123 Main Street')
      end
    end

    context 'when place_id does not exist' do
      subject(:service) { described_class.new(999_999) }

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
              'osm_id' => 99_999
              # Missing name, city, country, etc.
            }
          }
        )
      end

      before do
        allow(Geocoder).to receive(:search).and_return([minimal_place])
      end

      it 'handles missing properties gracefully' do
        expect { service.call }.not_to raise_error
      end

      it 'still marks the place as geocoded' do
        expect { service.call }.to change { place.reload.reverse_geocoded_at }.from(nil)
      end
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Places::NameFetcher do
  describe '#call' do
    subject(:service) { described_class.new(place) }

    let(:place) do
      create(
        :place,
        name: Place::DEFAULT_NAME,
        city: nil,
        country: nil,
        geodata: {},
        lonlat: 'POINT(10.0 10.0)'
      )
    end

    let(:geocoder_result) do
      double(
        'geocoder_result',
        data: {
          'properties' => {
            'name' => 'Central Park',
            'city' => 'New York',
            'country' => 'United States'
          }
        }
      )
    end

    before do
      allow(Geocoder).to receive(:search).and_return([geocoder_result])
    end

    context 'when geocoding is successful' do
      it 'calls Geocoder with correct parameters' do
        expect(Geocoder).to receive(:search)
          .with([place.lat, place.lon], units: :km, limit: 1, distance_sort: true)
          .and_return([geocoder_result])

        service.call
      end

      it 'updates place name from geocoder data' do
        expect { service.call }.to change(place, :name)
          .from(Place::DEFAULT_NAME)
          .to('Central Park')
      end

      it 'updates place city from geocoder data' do
        expect { service.call }.to change(place, :city)
          .from(nil)
          .to('New York')
      end

      it 'updates place country from geocoder data' do
        expect { service.call }.to change(place, :country)
          .from(nil)
          .to('United States')
      end

      it 'saves the place' do
        expect(place).to receive(:save!)

        service.call
      end

      context 'when DawarichSettings.store_geodata? is enabled' do
        before do
          allow(DawarichSettings).to receive(:store_geodata?).and_return(true)
        end

        it 'stores geodata in the place' do
          expect { service.call }.to change(place, :geodata)
            .from({})
            .to(geocoder_result.data)
        end
      end

      context 'when DawarichSettings.store_geodata? is disabled' do
        before do
          allow(DawarichSettings).to receive(:store_geodata?).and_return(false)
        end

        it 'does not store geodata in the place' do
          expect { service.call }.not_to change(place, :geodata)
        end
      end

      context 'when place has visits with default name' do
        let!(:visit_with_default_name) do
          create(:visit, name: Place::DEFAULT_NAME)
        end
        let!(:visit_with_custom_name) do
          create(:visit, name: 'Custom Visit Name')
        end

        before do
          place.visits << visit_with_default_name
          place.visits << visit_with_custom_name
        end

        it 'updates visits with default name to the new place name' do
          expect { service.call }.to \
            change { visit_with_default_name.reload.name }
              .from(Place::DEFAULT_NAME)
              .to('Central Park')
        end

        it 'does not update visits with custom names' do
          expect { service.call }.not_to \
            change { visit_with_custom_name.reload.name }
        end
      end

      context 'when using transactions' do
        it 'wraps updates in a transaction' do
          expect(ActiveRecord::Base).to \
            receive(:transaction).and_call_original

          service.call
        end

        it 'rolls back changes if save fails' do
          allow(place).to receive(:save!).and_raise(ActiveRecord::RecordInvalid)

          expect { service.call }.to raise_error(ActiveRecord::RecordInvalid)
          expect(place.reload.name).to eq(Place::DEFAULT_NAME)
        end
      end

      it 'returns the updated place' do
        result = service.call
        expect(result).to eq(place)
        expect(result.name).to eq('Central Park')
      end
    end

    context 'when geocoding returns no results' do
      before do
        allow(Geocoder).to receive(:search).and_return([])
      end

      it 'returns nil' do
        expect(service.call).to be_nil
      end

      it 'does not update the place' do
        expect { service.call }.not_to change(place, :name)
      end

      it 'does not call save on the place' do
        expect(place).not_to receive(:save!)

        service.call
      end
    end

    context 'when geocoding returns nil result' do
      before do
        allow(Geocoder).to receive(:search).and_return([nil])
      end

      it 'returns nil' do
        expect(service.call).to be_nil
      end

      it 'does not update the place' do
        expect { service.call }.not_to change(place, :name)
      end
    end

    context 'when geocoder result has missing properties' do
      let(:incomplete_geocoder_result) do
        double(
          'geocoder_result',
          data: {
            'properties' => {
              'name' => 'Partial Place',
              'city' => nil,
              'country' => 'United States'
            }
          }
        )
      end

      before do
        allow(Geocoder).to receive(:search).and_return([incomplete_geocoder_result])
      end

      it 'updates place with available data' do
        service.call

        expect(place.name).to eq('Partial Place')
        expect(place.city).to be_nil
        expect(place.country).to eq('United States')
      end
    end

    context 'when geocoder result has no properties' do
      let(:no_properties_result) do
        double('geocoder_result', data: {})
      end

      before do
        allow(Geocoder).to receive(:search).and_return([no_properties_result])
      end

      it 'handles missing properties gracefully' do
        expect { service.call }.not_to raise_error

        expect(place.name).to eq(Place::DEFAULT_NAME)
        expect(place.city).to be_nil
        expect(place.country).to be_nil
      end
    end
  end
end

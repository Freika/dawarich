# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ReverseGeocoding::Points::FetchData do
  subject(:fetch_data) { described_class.new(point.id).call }

  let(:point) { create(:point) }

  context 'when Geocoder returns city and country' do
    let!(:germany) { create(:country, name: 'Germany', iso_a2: 'DE', iso_a3: 'DEU') }

    before do
      allow(Geocoder).to receive(:search).and_return(
        [
          double(
            city: 'Berlin',
            country: 'Germany',
            data: {
              'address' => 'Address',
              'properties' => { 'countrycode' => 'DE' }
            }
          )
        ]
      )
    end

    context 'when point does not have city and country' do
      it 'updates point with city and country' do
        expect { fetch_data }.to change { point.reload.city }
          .from(nil).to('Berlin')
          .and change { point.reload.country_id }.from(nil).to(germany.id)
      end

      it 'finds existing country' do
        fetch_data
        country = point.reload.country
        expect(country.name).to eq('Germany')
        expect(country.iso_a2).to eq('DE')
        expect(country.iso_a3).to eq('DEU')
      end

      it 'updates point with geodata' do
        expect { fetch_data }.to change { point.reload.geodata }.from({}).to(
          'address' => 'Address',
          'properties' => { 'countrycode' => 'DE' }
        )
      end

      it 'calls Geocoder' do
        fetch_data

        expect(Geocoder).to have_received(:search).with([point.lat, point.lon])
      end

      context 'when store_geodata? is disabled' do
        before do
          allow(DawarichSettings).to receive(:store_geodata?).and_return(false)
        end

        it 'does not store geodata' do
          expect { fetch_data }.not_to(change { point.reload.geodata })
        end

        it 'still updates city and country' do
          expect { fetch_data }.to change { point.reload.city }
            .from(nil).to('Berlin')
        end
      end
    end

    context 'when point has city and country' do
      let(:country) { create(:country, name: 'Test Country') }
      let(:point) do
        create(:point, :with_geodata, city: 'Test City', country_id: country.id, reverse_geocoded_at: Time.current)
      end

      before do
        allow(Geocoder).to receive(:search).and_return(
          [double(
            geodata: { 'address' => 'Address' },
            city: 'Berlin',
            country: 'Germany',
            data: {
              'address' => 'Address',
              'properties' => { 'countrycode' => 'DE' }
            }
          )]
        )
      end

      it 'does not update point' do
        expect { fetch_data }.not_to(change { point.reload.city })
      end

      it 'does not call Geocoder' do
        fetch_data

        expect(Geocoder).not_to have_received(:search)
      end
    end
  end

  context 'when Geocoder returns country name that does not exist in database' do
    before do
      allow(Geocoder).to receive(:search).and_return(
        [
          double(
            city: 'Paris',
            country: 'NonExistentCountry',
            data: {
              'address' => 'Address',
              'properties' => { 'city' => 'Paris' }
            }
          )
        ]
      )
    end

    it 'does not set country_id when country is not found' do
      expect { fetch_data }.to change { point.reload.city }
        .from(nil).to('Paris')

      expect(point.reload.country_id).to be_nil
    end
  end

  context 'when Geocoder returns an error' do
    before do
      allow(Geocoder).to receive(:search).and_return([double(city: nil, country: nil, data: { 'error' => 'Error' })])
    end

    it 'does not update point' do
      expect { fetch_data }.not_to(change { point.reload.city })
    end
  end
end

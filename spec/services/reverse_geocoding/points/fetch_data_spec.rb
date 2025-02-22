# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ReverseGeocoding::Points::FetchData do
  subject(:fetch_data) { described_class.new(point.id).call }

  let(:point) { create(:point) }

  context 'when Geocoder returns city and country' do
    before do
      allow(Geocoder).to receive(:search).and_return([double(city: 'City', country: 'Country',
                                                             data: { 'address' => 'Address' })])
    end

    context 'when point does not have city and country' do
      it 'updates point with city and country' do
        expect { fetch_data }.to change { point.reload.city }
          .from(nil).to('City')
          .and change { point.reload.country }.from(nil).to('Country')
      end

      it 'updates point with geodata' do
        expect { fetch_data }.to change { point.reload.geodata }.from({}).to('address' => 'Address')
      end

      it 'calls Geocoder' do
        fetch_data

        expect(Geocoder).to have_received(:search).with([point.lat, point.lon])
      end
    end

    context 'when point has city and country' do
      let(:point) { create(:point, :with_geodata, :reverse_geocoded) }

      before do
        allow(Geocoder).to receive(:search).and_return(
          [double(geodata: { 'address' => 'Address' }, city: 'City', country: 'Country')]
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

  context 'when Geocoder returns an error' do
    before do
      allow(Geocoder).to receive(:search).and_return([double(data: { 'error' => 'Error' })])
    end

    it 'does not update point' do
      expect { fetch_data }.not_to(change { point.reload.city })
    end
  end
end

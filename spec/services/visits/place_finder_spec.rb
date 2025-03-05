# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Visits::PlaceFinder do
  let(:user) { create(:user) }

  subject { described_class.new(user) }

  describe '#find_or_create_place' do
    let(:visit_data) do
      {
        center_lat: 40.7128,
        center_lon: -74.0060,
        suggested_name: 'Test Place'
      }
    end

    context 'when an existing place is found' do
      let!(:existing_place) { create(:place, latitude: 40.7128, longitude: -74.0060) }

      it 'returns the existing place' do
        place = subject.find_or_create_place(visit_data)

        expect(place).to eq(existing_place)
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
          latitude: 40.7128,
          longitude: -74.0060
        )
      end

      before do
        allow(Geocoder).to receive(:search).and_return([geocoder_result])
        allow(subject).to receive(:process_nearby_organizations)
      end

      it 'creates a new place with geocoded data' do
        expect do
          subject.find_or_create_place(visit_data)
        end.to change(Place, :count).by(1)

        place = Place.last

        expect(place.name).to include('Test Location')
        expect(place.city).to eq('Test City')
        expect(place.country).to eq('Test Country')
        expect(place.source).to eq('photon')
      end

      context 'when geocoding returns no results' do
        before do
          allow(Geocoder).to receive(:search).and_return([])
        end

        it 'creates a place with the suggested name' do
          expect do
            subject.find_or_create_place(visit_data)
          end.to change(Place, :count).by(1)

          place = Place.last

          expect(place.name).to eq('Test Place')
          expect(place.source).to eq('manual')
        end
      end
    end
  end
end

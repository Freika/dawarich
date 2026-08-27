# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Curated places keep their manual source through reverse geocoding' do
  subject(:service) { ReverseGeocoding::Places::FetchData.new(place.id) }

  let(:user) { create(:user) }
  let(:geocoded_place) do
    double(
      data: {
        'geometry' => { 'coordinates' => [13.0948638, 54.2905245] },
        'properties' => {
          'osm_id' => 12_345,
          'name' => 'Some Cafe',
          'osm_value' => 'cafe',
          'city' => 'Berlin',
          'country' => 'Germany',
          'postcode' => '10115',
          'street' => 'Test Street',
          'housenumber' => '1'
        }
      }
    )
  end

  before do
    allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(true)
    allow(Geocoder).to receive(:search).and_return([geocoded_place])
  end

  context 'when the user created and named the place' do
    let(:place) do
      create(:place, user: user, name: 'Home', source: :manual, user_named: true)
    end

    it 'keeps the manual source' do
      expect { service.call }.not_to(change { place.reload.source })
      expect(place.reload).to be_manual
    end

    it 'keeps the place ranked ahead of machine-minted neighbours' do
      create(:place, user: user, name: 'Greifswalder Chaussee 1', source: :photon,
                     latitude: place.latitude, longitude: place.longitude)

      service.call

      found = Visits::PlaceFinder.new(user).find_or_create_place(
        center_lat: place.latitude.to_f, center_lon: place.longitude.to_f, suggested_name: nil
      )

      expect(found.id).to eq(place.id)
    end

    it 'still refreshes the geocoded payload' do
      expect { service.call }.to change { place.reload.reverse_geocoded_at }.from(nil)
      expect(place.reload.city).to eq('Berlin')
    end
  end

  context 'when the place was minted by the detector' do
    let(:place) { create(:place, user: user, name: Place::DEFAULT_NAME, source: :photon) }

    it 'stays on the photon source' do
      service.call

      expect(place.reload).to be_photon
    end
  end

  describe 'sibling places returned by the same lookup' do
    let(:place) { create(:place, user: user, name: Place::DEFAULT_NAME, source: :photon) }
    let(:sibling_payload) do
      {
        'geometry' => { 'coordinates' => [13.1, 54.3] },
        'properties' => {
          'osm_id' => 67_890,
          'name' => 'Second Place',
          'osm_value' => 'cafe',
          'city' => 'Berlin',
          'country' => 'Germany'
        }
      }
    end

    before do
      allow(Geocoder).to receive(:search).and_return([geocoded_place, double(data: sibling_payload)])
    end

    it 'does not downgrade a curated sibling' do
      sibling = create(
        :place,
        user: user,
        name: 'Corner Shop',
        source: :manual,
        user_named: true,
        geodata: { 'properties' => { 'osm_id' => 67_890 } }
      )

      service.call

      expect(sibling.reload).to be_manual
      expect(sibling.name).to eq('Corner Shop')
    end
  end
end

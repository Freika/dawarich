# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Nominatim naming and stored geodata' do
  let(:user) { create(:user) }
  let(:place) { create(:place, user: user, name: Place::DEFAULT_NAME, lonlat: 'POINT(13.405 52.52)') }
  let(:data) do
    {
      'lat' => '52.52', 'lon' => '13.405', 'osm_id' => 123, 'type' => 'house',
      'display_name' => '51, Example Road, Berlin, Germany',
      'address' => { 'house_number' => '51', 'road' => 'Example Road', 'city' => 'Berlin', 'country' => 'Germany' }
    }
  end
  let(:result) { double(data: data) }

  before do
    allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(true)
    allow(Geocoding::Search).to receive(:call).and_return([result])
  end

  it 'names an unnamed place from the flat provider address' do
    Places::NameFetcher.new(place).call

    expect(place.reload.name).to eq('Example Road, 51, Berlin')
    expect(place.city).to eq('Berlin')
    expect(place.country).to eq('Germany')
  end

  it 'preserves a manual name while updating its location details' do
    place.update!(name: 'My home', user_named: true)

    Places::NameFetcher.new(place).call

    expect(place.reload.name).to eq('My home')
    expect(place.city).to eq('Berlin')
  end

  it 'uses the street address instead of a bare house number in reverse lookup' do
    ReverseGeocoding::Places::FetchData.new(place.id).call

    expect(place.reload.name).to eq('Example Road 51 (House)')
  end

  [nil, [], [1], true, 42, 'legacy'].each do |data|
    it "ignores stored geodata of shape #{data.inspect}" do
      expect(Geocoding::ResultNormalizer.from_data(data)).to eq(properties: {}, coords: nil)
    end
  end

  [
    { 'hamlet' => 'Small Village', 'highway' => 'Old Road' },
    { 'municipality' => 'Small Village', 'footway' => 'Old Road' }
  ].each do |address_fields|
    context "with fallback address fields #{address_fields.keys.join(', ')}" do
      before do
        data['address'] = address_fields.merge('house_number' => '51', 'state' => 'Test State', 'country' => 'Germany')
      end

      it 'uses the same address fields for existing-place naming and place search' do
        Places::NameFetcher.new(place).call
        formatted = Places::PhotonResultFormatter.call(result)

        expect(place.reload.name).to eq('Old Road, 51, Small Village, Test State')
        expect(place.city).to eq('Small Village')
        expect(formatted).to include(street: 'Old Road', city: 'Small Village', housenumber: '51')
      end

      it 'keeps the same fallbacks when refreshing reverse-geocoded places' do
        ReverseGeocoding::Places::FetchData.new(place.id).call

        expect(place.reload.name).to eq('Old Road 51 (House)')
        expect(place.city).to eq('Small Village')
      end

      it 'includes the same address and state in visit name suggestions' do
        data.merge!('name' => 'Coffee Shop', 'type' => 'cafe', 'class' => 'amenity')

        expect(Visits::Names::Suggester.new([double(geodata: data)]).call)
          .to eq('Coffee Shop, Old Road, Small Village, Test State')
      end
    end
  end
end

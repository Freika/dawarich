# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Places::NameFetcher renames places after geocoding even when the response lacks a top-level name' do
  let(:place) do
    create(
      :place,
      name: Place::DEFAULT_NAME,
      city: nil,
      country: nil,
      geodata: {},
      lonlat: 'POINT(13.405 52.52)'
    )
  end

  let(:residential_geocoder_result) do
    double(
      'geocoder_result',
      data: {
        'properties' => {
          'street' => 'Hauptstrasse',
          'housenumber' => '5',
          'city' => 'Berlin',
          'state' => 'Berlin',
          'country' => 'Germany'
        }
      }
    )
  end

  before do
    allow(Geocoder).to receive(:search).and_return([residential_geocoder_result])
  end

  it 'assembles a name from street, city, and state when name is absent' do
    Places::NameFetcher.new(place).call

    expect(place.reload.name).to eq('Hauptstrasse, 5, Berlin')
    expect(place.city).to eq('Berlin')
    expect(place.country).to eq('Germany')
  end

  it 'renames linked visits to the assembled name' do
    visit_with_default = create(:visit, name: Place::DEFAULT_NAME)
    visit_with_custom = create(:visit, name: 'Coffee with Anna')
    place.visits << visit_with_default
    place.visits << visit_with_custom

    Places::NameFetcher.new(place).call

    expect(visit_with_default.reload.name).to eq('Hauptstrasse, 5, Berlin')
    expect(visit_with_custom.reload.name).to eq('Coffee with Anna')
  end

  context 'when the geocoder response has no name-building components at all' do
    let(:nameless_result) do
      double('geocoder_result', data: { 'properties' => { 'country' => 'Germany' } })
    end

    before do
      allow(Geocoder).to receive(:search).and_return([nameless_result])
    end

    it 'leaves the place at the default name' do
      Places::NameFetcher.new(place).call

      expect(place.reload.name).to eq(Place::DEFAULT_NAME)
      expect(place.country).to eq('Germany')
    end
  end
end

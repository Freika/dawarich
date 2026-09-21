# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Places::NameFetcher renames places after geocoding even when the response lacks a top-level name' do
  before { configure_instance_geocoding }

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

  it 'refreshes linked Visit location labels without changing custom names' do
    visit_with_default = create(:visit, name: nil, location_label: Place::DEFAULT_NAME)
    visit_with_custom = create(:visit, name: 'Coffee with Anna', location_label: Place::DEFAULT_NAME)
    place.visits << visit_with_default
    place.visits << visit_with_custom

    Places::NameFetcher.new(place).call

    expect(visit_with_default.reload).to have_attributes(name: nil, location_label: 'Hauptstrasse, 5, Berlin')
    expect(visit_with_custom.reload).to have_attributes(
      name: 'Coffee with Anna', location_label: 'Hauptstrasse, 5, Berlin'
    )
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

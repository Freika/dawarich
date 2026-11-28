# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Place address line from different geocoder shapes' do
  let(:user) { create(:user) }

  def place_with(geodata)
    build(:place, user: user, geodata: geodata)
  end

  it 'formats Photon-shaped geodata' do
    place = place_with('properties' => { 'street' => 'Hauptstraße', 'housenumber' => '12',
                                         'postcode' => '04275', 'city' => 'Leipzig' })

    expect(place.address_line).to eq('Hauptstraße 12, 04275 Leipzig')
  end

  it 'formats Nominatim-shaped geodata' do
    place = place_with('lat' => '51.3', 'lon' => '12.4', 'display_name' => 'Hauptstraße 12, Leipzig',
                       'address' => { 'road' => 'Hauptstraße', 'house_number' => '12',
                                      'postcode' => '04275', 'city' => 'Leipzig' })

    expect(place.address_line).to eq('Hauptstraße 12, 04275 Leipzig')
  end

  it 'returns nil without geodata' do
    expect(place_with({}).address_line).to be_nil
    expect(place_with(nil).address_line).to be_nil
  end
end

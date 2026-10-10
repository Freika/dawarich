# frozen_string_literal: true

# This formatter is deliberately independent of Rails and provider availability.
module Families; end
require_relative '../../../app/services/families/location_address'

RSpec.describe Families::LocationAddress do
  def address(data, city: nil, country: nil)
    point = Struct.new(:geodata, :city, :country_name).new(data, city, country)
    described_class.call(point)
  end

  it 'formats Photon data without exposing raw provider metadata' do
    data = { 'properties' => { 'street' => 'Example Street', 'housenumber' => '12',
                              'city' => 'Example City', 'country' => 'Example Country', 'osm_id' => 123 } }
    expect(address(data)).to eq('Example Street 12, Example City, Example Country')
  end

  it 'formats Nominatim and LocationIQ address data' do
    data = { 'address' => { 'road' => 'Example Road', 'house_number' => '5', 'town' => 'Example Town' } }
    expect(address(data)).to eq('Example Road 5, Example Town')
  end

  it 'formats Geoapify properties' do
    expect(address({ 'properties' => { 'street' => 'Example Street', 'housenumber' => '3',
'city' => 'Example City' } }))
      .to eq('Example Street 3, Example City')
  end

  it 'uses available locality data when street details are absent' do
    expect(address({}, city: 'Example City', country: 'Example Country')).to eq('Example City, Example Country')
    expect(address({ 'address' => { 'village' => 'Example Village' } })).to eq('Example Village')
  end

  it 'ignores malformed and blank fields and never shows a house number alone' do
    expect(address({ 'properties' => { 'street' => [], 'housenumber' => '12', 'city' => '  ' } })).to be_nil
    expect(address({ 'properties' => 'invalid', 'address' => [] })).to be_nil
    expect(address(nil)).to be_nil
  end

  it 'trims whitespace and removes duplicate locality labels' do
    expect(address({ 'properties' => { 'city' => ' Example ', 'country' => 'Example' } })).to eq('Example')
  end
end

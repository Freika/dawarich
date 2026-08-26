# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Visits::Detection::PlaceAttributor do
  let(:user) { create(:user) }
  let(:policy) { Visits::Detection::Policy.for(user) }
  let(:lat0) { 51.3402 }
  let(:lon0) { 12.3712 }

  before do
    allow(DawarichSettings).to receive_messages(reverse_geocoding_enabled?: true, store_geodata?: false)
  end

  def north(meters) = meters / 111_320.0

  def stay(point_ids: [])
    { center_lat: lat0, center_lon: lon0, point_ids: point_ids, radius: 20 }
  end

  def attribute(stay_hash = stay)
    described_class.new(user, policy).call(stay_hash)
  end

  it 'assigns a containing area with the strongest evidence' do
    area = create(:area, user: user, latitude: lat0, longitude: lon0, radius: 200)
    create(:place, user: user, latitude: lat0, longitude: lon0)

    result = attribute

    expect(result[:evidence]).to eq(:area)
    expect(result[:area]).to eq(area)
    expect(result[:place]).to be_nil
    expect(result[:name]).to eq(area.name)
  end

  it 'prefers a manual place over a closer photon one' do
    create(:place, user: user, source: :photon, latitude: lat0 + north(5), longitude: lon0, name: 'Photon Guess')
    manual = create(:place, user: user, source: :manual, latitude: lat0 + north(35), longitude: lon0, name: 'My Spot')

    result = attribute

    expect(result[:evidence]).to eq(:place)
    expect(result[:place]).to eq(manual)
    expect(result[:name]).to eq('My Spot')
  end

  it 'boosts a place the user has confirmed visits at' do
    create(:place, user: user, source: :photon, latitude: lat0 + north(5), longitude: lon0, name: 'Closer Stranger')
    known = create(:place, user: user, source: :photon, name: 'The Regular',
                           latitude: lat0 + north(35), longitude: lon0)
    create_list(:visit, 2, user: user, place: known, status: :confirmed)

    expect(attribute[:place]).to eq(known)
  end

  it 'ignores places beyond the attribution radius' do
    create(:place, user: user, latitude: lat0 + north(300), longitude: lon0, name: 'Too Far')

    expect(attribute[:evidence]).not_to eq(:place)
  end

  it 'names a stay from its own points geodata and mints the place' do
    points = create_list(:point, 3, user: user, geodata: {
                           'features' => [{ 'properties' => { 'type' => 'cafe', 'name' => 'Café Central' } }]
                         })

    result = nil
    expect { result = attribute(stay(point_ids: points.map(&:id))) }.to change { Place.count }.by(1)

    expect(result[:evidence]).to eq(:poi)
    expect(result[:name]).to eq('Café Central')
    expect(result[:place].name).to eq('Café Central')
  end

  it 'skips the reverse lookup when point geodata already names the stay' do
    points = create_list(:point, 3, user: user, geodata: {
                           'features' => [{ 'properties' => { 'type' => 'cafe', 'name' => 'Café Central' } }]
                         })
    allow(Geocoder).to receive(:search)

    result = attribute(stay(point_ids: points.map(&:id)))

    expect(result[:evidence]).to eq(:poi)
    expect(Geocoder).not_to have_received(:search)
  end

  it 'promotes a reverse-geocoded venue sitting inside the stay to a minted place' do
    geocoder_result = double(data: {
                               'geometry' => { 'coordinates' => [lon0, lat0] },
                               'properties' => { 'osm_key' => 'amenity', 'name' => 'Café Pushkin' }
                             })
    allow(Geocoder).to receive(:search).and_return([geocoder_result])

    result = nil
    expect { result = attribute }.to change { Place.count }.by(1)

    expect(result[:evidence]).to eq(:poi)
    expect(result[:name]).to eq('Café Pushkin')
  end

  it 'promotes a Nominatim-shaped reverse result to a minted place' do
    geocoder_result = double(data: {
                               'lat' => lat0.to_s, 'lon' => lon0.to_s, 'name' => 'Café Pushkin',
                               'category' => 'amenity', 'type' => 'cafe', 'osm_id' => 5,
                               'osm_type' => 'node',
                               'address' => { 'road' => 'Karlstraße', 'house_number' => '1',
                                              'city' => 'Leipzig', 'country' => 'Germany' }
                             })
    allow(Geocoder).to receive(:search).and_return([geocoder_result])

    result = nil
    expect { result = attribute }.to change { Place.count }.by(1)

    expect(result[:evidence]).to eq(:poi)
    expect(result[:name]).to eq('Café Pushkin')
  end

  it 'refuses venue evidence for a street-keyed feature, naming by street instead' do
    geocoder_result = double(data: {
                               'geometry' => { 'coordinates' => [lon0, lat0] },
                               'properties' => { 'osm_key' => 'highway', 'name' => 'Karl-Liebknecht-Straße' }
                             })
    allow(Geocoder).to receive(:search).and_return([geocoder_result])

    result = nil
    expect { result = attribute }.not_to(change { Place.count })

    expect(result[:evidence]).to eq(:address)
    expect(result[:name]).to eq('Karl-Liebknecht-Straße')
  end

  it 'falls back to an address-only name without minting a place' do
    geocoder_result = double(data: { 'properties' => {
                               'street' => 'Stargarder Straße', 'housenumber' => '65',
                               'city' => 'Berlin', 'name' => 'Vegan Haus'
                             } })
    allow(Geocoder).to receive(:search).and_return([geocoder_result])

    result = nil
    expect { result = attribute }.not_to(change { Place.count })

    expect(result[:evidence]).to eq(:address)
    expect(result[:name]).to eq('Stargarder Straße 65')
    expect(result[:place]).to be_nil
  end

  it 'returns honest nothing when there is no evidence at all' do
    allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(false)

    result = attribute

    expect(result[:evidence]).to eq(:none)
    expect(result[:name]).to be_nil
    expect(result[:place]).to be_nil
    expect(result[:area]).to be_nil
  end
end

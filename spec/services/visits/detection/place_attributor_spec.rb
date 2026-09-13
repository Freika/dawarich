# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Visits::Detection::PlaceAttributor do
  let(:user) { create(:user) }
  let(:policy) { Visits::Detection::Policy.for(user) }
  let(:lat0) { 51.3402 }
  let(:lon0) { 12.3712 }
  let(:geocoding_configured) { true }

  before do
    configure_instance_geocoding if geocoding_configured
    allow(DawarichSettings).to receive(:store_geodata?).and_return(false)
  end

  def north(meters) = meters / 111_320.0

  def stay(point_ids: [])
    { center_lat: lat0, center_lon: lon0, point_ids: point_ids, radius: 20 }
  end

  def attribute(stay_hash = stay)
    described_class.new(user, policy).call(stay_hash)
  end

  it 'lazily converts an unmigrated Area and returns its canonical Place' do
    area = create(:area, user: user, latitude: lat0, longitude: lon0, radius: 200)
    create(:place, user: user, latitude: lat0, longitude: lon0)

    result = attribute

    expect(result[:evidence]).to eq(:place)
    expect(result[:area]).to be_nil
    expect(result[:place]).to eq(LegacyAreaPlaceMapping.find_by!(area:).place)
    expect(result[:name]).to eq(area.name)
  end

  it 'prefers the smallest containing Place' do
    create(:place, user: user, latitude: lat0 + north(5), longitude: lon0,
                   visit_radius: 100, name: 'Broad Place')
    specific = create(:place, user: user, latitude: lat0 + north(20), longitude: lon0,
                              visit_radius: 25, name: 'Specific Place')

    result = attribute

    expect(result[:evidence]).to eq(:place)
    expect(result[:place]).to eq(specific)
    expect(result[:name]).to eq('Specific Place')
  end

  it 'prefers the nearest center when containing Places have equal radii' do
    nearest = create(:place, user: user, latitude: lat0 + north(5), longitude: lon0, visit_radius: 50)
    create(:place, user: user, latitude: lat0 + north(25), longitude: lon0, visit_radius: 50)

    expect(attribute[:place]).to eq(nearest)
  end

  it 'uses stable Place ID as the final tie-breaker' do
    first = create(:place, user: user, latitude: lat0, longitude: lon0, visit_radius: 50)
    create(:place, user: user, latitude: lat0, longitude: lon0, visit_radius: 50)

    expect(attribute[:place]).to eq(first)
  end

  it 'ignores places beyond their own Visit Radius' do
    create(:place, user: user, latitude: lat0 + north(60), longitude: lon0,
                   visit_radius: 50, name: 'Too Far')

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
    expect(result[:location_label]).to eq('Stargarder Straße 65')
    expect(result[:place]).to be_nil
  end

  context 'when geocoding is not configured' do
    let(:geocoding_configured) { false }

    it 'returns honest nothing when there is no evidence at all' do
      result = attribute

      expect(result[:evidence]).to eq(:none)
      expect(result[:name]).to be_nil
      expect(result[:place]).to be_nil
      expect(result[:area]).to be_nil
    end
  end
  [
    { 'type' => 'house', 'category' => 'building' },
    { 'type' => 'residential', 'category' => 'highway', 'name' => 'Hauptstraße' },
    { 'type' => 'residential', 'class' => 'highway', 'name' => 'Hauptstraße' }
  ].each do |classification|
    it "keeps flat #{classification.inspect} geodata as address evidence" do
      data = classification.merge(
        'lat' => lat0.to_s, 'lon' => lon0.to_s,
        'address' => { 'road' => 'Hauptstraße', 'house_number' => '51', 'city' => 'Leipzig' }
      )
      points = create_list(:point, 2, user: user, geodata: data)
      allow(Geocoder).to receive(:search).and_return([double(data: data)])

      result = nil
      expect { result = attribute(stay(point_ids: points.map(&:id))) }.not_to(change { Place.count })

      expect(result[:evidence]).to eq(:address)
      expect(result[:name]).to eq('Hauptstraße 51')
      expect(result[:place]).to be_nil
    end
  end
end

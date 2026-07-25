# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Visits::PlaceFinder do
  let(:user) { create(:user) }
  let(:center_lat) { 52.5126 }
  let(:center_lon) { 13.4012 }
  let(:visit_data) do
    {
      center_lat: center_lat,
      center_lon: center_lon,
      suggested_name: '123 Fourth Street',
      points: [],
      start_time: Time.zone.now.to_i,
      end_time: (Time.zone.now + 1.hour).to_i,
      duration: 3600
    }
  end

  before do
    allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(true)
    allow(DawarichSettings).to receive(:store_geodata?).and_return(false)
  end

  def place_at(lat, lon, name:, source:)
    create(:place, user: user, name: name, source: source,
                   latitude: lat, longitude: lon, lonlat: "POINT(#{lon} #{lat})", geodata: {})
  end

  it 'returns the manual place even when a photon place matches the reverse-geocoded name' do
    photon = place_at(center_lat, center_lon, name: '123 Fourth Street', source: :photon)
    manual = place_at(center_lat, center_lon, name: 'My Favorite Address', source: :manual)

    result = described_class.new(user).find_or_create_place(visit_data)

    expect(result).to eq(manual)
    expect(result).not_to eq(photon)
  end

  it 'reuses a manual place near the cluster instead of minting a new photon place' do
    # ~70 m north of the center — outside the 50 m photon similarity radius.
    manual = place_at(center_lat + 0.00063, center_lon, name: 'My Favorite Address', source: :manual)

    result = nil
    expect { result = described_class.new(user).find_or_create_place(visit_data) }
      .not_to(change { Place.count })
    expect(result).to eq(manual)
  end
end

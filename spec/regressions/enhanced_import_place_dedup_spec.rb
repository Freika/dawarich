# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Extracted places reuse an existing pin only when it is the same place' do
  let(:user) { create(:user) }
  let(:import) { create(:import, user: user, source: :google_phone_takeout) }
  let(:writer) { EnhancedImport::Writers::PlaceWriter.new(user, import) }

  def extracted(name:, lat: 51.3402, lon: 12.3712, external_id: "google:#{name}")
    EnhancedImport::Extracted::Place.new(
      external_place_id: external_id,
      name: name,
      latitude: lat,
      longitude: lon,
      semantic_type: nil,
      geodata_extras: {}
    )
  end

  it 'reuses a Dawarich-geocoded place with the same name at the same spot' do
    existing = create(:place, user: user, name: 'Home', latitude: 51.3402, longitude: 12.3712,
                              lonlat: 'POINT(12.3712 51.3402)')

    place, created = writer.upsert(extracted(name: 'Home'))

    expect(created).to be false
    expect(place.id).to eq(existing.id)
  end

  it 'does not collapse a different place that merely sits nearby' do
    create(:place, user: user, name: 'Bakery', latitude: 51.3402, longitude: 12.3712,
                   lonlat: 'POINT(12.3712 51.3402)')

    place, created = writer.upsert(extracted(name: 'Home'))

    expect(created).to be true
    expect(place.name).to eq('Home')
    expect(Place.where(user_id: user.id).count).to eq(2)
  end

  it 'keeps two distinct Google places within the radius apart' do
    first, = writer.upsert(extracted(name: 'Home'))
    second, = writer.upsert(extracted(name: 'Office', lat: 51.34025, lon: 12.37125))

    expect(first.id).not_to eq(second.id)
    expect(Place.where(user_id: user.id).pluck(:name)).to contain_exactly('Home', 'Office')
  end

  it 'still prefers an exact external id match' do
    place_one, = writer.upsert(extracted(name: 'Home'))
    place_two, created = writer.upsert(extracted(name: 'Home'))

    expect(created).to be false
    expect(place_two.id).to eq(place_one.id)
  end
end

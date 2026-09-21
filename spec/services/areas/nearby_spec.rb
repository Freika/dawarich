# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Areas::Nearby do
  let(:user) { create(:user) }
  let(:lat) { 52.437 }
  let(:lon) { 13.539 }

  it 'returns the user areas within the radius, formatted with source: area' do
    near = create(:area, user: user, name: 'Home', latitude: lat, longitude: lon, radius: 100)
    create(:area, user: user, name: 'Far Away', latitude: 53.5, longitude: 14.5, radius: 100)

    results = described_class.new(user: user, latitude: lat, longitude: lon, radius: 1.0).call

    expect(results.size).to eq(1)
    expect(results.first).to include(id: near.id, name: 'Home', source: 'area', radius: 100)
    expect(results.first[:latitude]).to be_within(0.0001).of(lat)
  end

  it 'does not return another user areas' do
    other = create(:user)
    create(:area, user: other, name: 'Theirs', latitude: lat, longitude: lon, radius: 100)

    results = described_class.new(user: user, latitude: lat, longitude: lon, radius: 1.0).call

    expect(results).to eq([])
  end

  it 'returns an area matched by name even when it is outside the radius' do
    create(:area, user: user, name: 'Home', latitude: lat, longitude: lon, radius: 100)
    far = create(:area, user: user, name: 'Grandma House', latitude: 48.137, longitude: 11.575, radius: 100)

    results = described_class.new(user: user, latitude: lat, longitude: lon, radius: 1.0, query: 'grandma').call

    expect(results.map { |r| r[:id] }).to include(far.id)
  end

  it 'filters and formats mapped Areas from the current canonical Place state' do
    area = create(:area, user: user, name: 'Old Home', latitude: 53.5, longitude: 14.5, radius: 25)
    place = create(:place, user: user, name: 'Current Home', latitude: lat, longitude: lon, visit_radius: 150)
    LegacyAreaPlaceMapping.create!(area: area, place: place)

    results = described_class.new(user: user, latitude: lat, longitude: lon, radius: 1.0).call

    expect(results).to contain_exactly(
      include(id: area.id, name: 'Current Home', latitude: place.lat, longitude: place.lon, radius: 150)
    )
  end

  it 'does not match another user area by name' do
    other = create(:user)
    create(:area, user: other, name: 'Grandma House', latitude: 48.137, longitude: 11.575, radius: 100)

    results = described_class.new(user: user, latitude: lat, longitude: lon, radius: 1.0, query: 'grandma').call

    expect(results).to eq([])
  end

  it 'caps results at MAX_RESULTS' do
    (Areas::Nearby::MAX_RESULTS + 2).times do |i|
      create(:area, user: user, name: "Spot #{i}", latitude: lat, longitude: lon, radius: 100)
    end

    results = described_class.new(user: user, latitude: lat, longitude: lon, radius: 1.0).call

    expect(results.size).to eq(Areas::Nearby::MAX_RESULTS)
  end
end

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

  it 'caps results at MAX_RESULTS' do
    (Areas::Nearby::MAX_RESULTS + 2).times do |i|
      create(:area, user: user, name: "Spot #{i}", latitude: lat, longitude: lon, radius: 100)
    end

    results = described_class.new(user: user, latitude: lat, longitude: lon, radius: 1.0).call

    expect(results.size).to eq(Areas::Nearby::MAX_RESULTS)
  end
end

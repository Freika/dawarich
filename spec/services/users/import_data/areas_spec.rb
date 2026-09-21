# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::ImportData::Areas, type: :service do
  let(:user) { create(:user) }
  let(:areas_data) do
    [
      {
        'id' => 91,
        'name' => 'Home',
        'latitude' => '40.7128',
        'longitude' => '-74.0060',
        'radius' => 100
      },
      {
        'id' => 92,
        'name' => 'Work',
        'latitude' => '40.7589',
        'longitude' => '-73.9851',
        'radius' => 50
      }
    ]
  end
  let(:service) { described_class.new(user, areas_data) }

  it 'imports legacy Areas as canonical Places without recreating Areas' do
    expect { service.call }.to change { user.places.count }.by(2)
    expect(user.areas.count).to eq(0)

    expect(user.places.find_by(name: 'Home')).to have_attributes(
      latitude: 40.7128,
      longitude: -74.0060,
      visit_radius: 100,
      source: 'manual'
    )
  end

  it 'exposes legacy IDs for Visit remapping' do
    service.call

    expect(service.place_references_by_id.fetch('91')).to include(
      'name' => 'Home',
      'visit_radius' => 100
    )
  end

  it 'reuses a same-name Place within 50 meters and keeps the larger radius' do
    existing = create(
      :place,
      user:,
      name: 'Home',
      latitude: 40.7128,
      longitude: -74.0060,
      visit_radius: 40
    )

    expect(service.call).to eq(1)
    expect(existing.reload.visit_radius).to eq(100)
    expect(user.places.where(name: 'Home').count).to eq(1)
  end

  it 'promotes a reused Photon Place to a user-owned locked Place' do
    existing = create(
      :place,
      user:,
      name: 'home',
      source: :photon,
      latitude: 40.7128,
      longitude: -74.0060,
      visit_radius: 40
    )

    service.call

    expect(existing.reload).to have_attributes(name: 'Home', source: 'manual', visit_radius: 100)
    expect(existing).to be_name_locked
  end

  it 'keeps a legacy name ambiguous after three same-name Areas' do
    input = [
      { 'id' => 1, 'name' => 'Home', 'latitude' => 40.0, 'longitude' => -74.0 },
      { 'id' => 2, 'name' => 'Home', 'latitude' => 41.0, 'longitude' => -75.0 },
      { 'id' => 3, 'name' => 'Home', 'latitude' => 42.0, 'longitude' => -76.0 }
    ]
    importer = described_class.new(user, input)

    importer.call

    expect(importer.place_references_by_id.keys).to contain_exactly('1', '2', '3')
    expect(importer.place_references_by_name).not_to have_key('home')
  end

  it 'does not merge different names based on proximity alone' do
    create(:place, user:, name: 'Apartment', latitude: 40.7128, longitude: -74.0060)

    expect { service.call }.to change { user.places.count }.by(2)
  end

  it 'skips invalid records' do
    input = ['invalid', { 'name' => 'Missing coordinates' }]

    expect(described_class.new(user, input).call).to eq(0)
  end

  it 'returns zero for non-array input' do
    expect(described_class.new(user, nil).call).to eq(0)
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Places::LegacyAreaAdapter do
  let(:user) { create(:user) }
  let(:adapter) { described_class.new(user:) }

  it 'resolves an Area to one canonical Place and records the stable mapping' do
    area = create(:area, user:, name: 'Home', radius: 175)

    first = adapter.resolve(area)
    second = adapter.resolve(area)

    expect(first).to eq(second)
    expect(first).to have_attributes(name: 'Home', visit_radius: 175)
    expect(LegacyAreaPlaceMapping.find_by!(area:).place).to eq(first)
  end

  it 'moves unplaced legacy Visits and notes when resolving during the transition' do
    area = create(:area, user:, name: 'Home')
    visit = create(:visit, user:, area:, place: nil)
    note = area.notes.create!(user:, body: 'Legacy note', noted_at: Time.current)

    place = adapter.resolve(area)

    expect(visit.reload).to have_attributes(place_id: place.id, area_id: nil, location_label: 'Home')
    expect(note.reload.attachable).to eq(place)
  end

  it 'creates and updates the compatibility shell together with its Place' do
    area, place = adapter.create(name: 'Work', latitude: 52.5, longitude: 13.4, radius: 90)

    expect(place).to have_attributes(name: 'Work', visit_radius: 90)

    adapter.update(area, name: 'Office', latitude: 52.51, longitude: 13.41, radius: 120)

    expect(area.reload).to have_attributes(name: 'Office', radius: 120)
    expect(place.reload).to have_attributes(name: 'Office', visit_radius: 120)
  end

  it 'deletes the Place and Area shell while preserving Visits' do
    area, place = adapter.create(name: 'Home', latitude: 52.5, longitude: 13.4, radius: 90)
    visit = create(:visit, user:, area:, place:)

    adapter.destroy(area)

    expect(visit.reload).to have_attributes(area_id: nil, place_id: nil)
  end

  it 'deletes every legacy alias of a shared Place so it cannot be recreated' do
    place = create(:place, user:, name: 'Home', latitude: 52.5, longitude: 13.4)
    first = create(:area, user:, name: 'Home', latitude: 52.5, longitude: 13.4)
    second = create(:area, user:, name: 'Home', latitude: 52.5, longitude: 13.4)
    LegacyAreaPlaceMapping.create!(area: first, place:)
    LegacyAreaPlaceMapping.create!(area: second, place:)

    adapter.destroy(first)

    expect(user.areas.where(id: [first.id, second.id])).to be_empty
    expect(Place.where(id: place.id)).to be_empty
  end
end

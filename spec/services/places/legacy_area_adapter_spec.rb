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

  it 'resolves an Area whose stored radius is not positive' do
    area = create(:area, user:)
    area.update_column(:radius, -5)

    expect(adapter.resolve(area).visit_radius).to eq(Place.column_defaults['visit_radius'])
  end

  it 'moves unplaced legacy Visits and notes when resolving during the transition' do
    area = create(:area, user:, name: 'Home')
    visit = create(:visit, user:, area:, place: nil)
    note = area.notes.create!(user:, body: 'Legacy note', noted_at: Time.current)

    place = adapter.resolve(area)

    expect(visit.reload).to have_attributes(place_id: place.id, area_id: nil, location_label: 'Home')
    expect(note.reload.attachable).to eq(place)
  end

  it 'keeps same-day notes on separate Places instead of merging their text' do
    noted_at = Time.zone.parse('2026-05-01 12:00:00')
    area = create(:area, user:, name: 'Home', latitude: 52.437, longitude: 13.539)
    existing = create(:place, user:, name: 'Home', latitude: 52.437, longitude: 13.539)
    place_note = create(:note, user:, attachable: existing, noted_at:, body: 'Place note')
    area_note = create(:note, user:, attachable: area, noted_at:, body: 'Area note')

    resolved = adapter.resolve(area)

    expect(resolved).not_to eq(existing)
    expect(place_note.reload.body).to eq('Place note')
    expect(area_note.reload).to have_attributes(body: 'Area note', attachable: resolved)
  end

  it 'returns the mapping another process created while resolving' do
    area = create(:area, user:)
    concurrent = create(:place, user:)
    allow(LegacyAreaPlaceMapping).to receive(:find_by).and_wrap_original do |original, *args, **kwargs|
      original.call(*args, **kwargs).tap do
        LegacyAreaPlaceMapping.create!(area:, place: concurrent) unless LegacyAreaPlaceMapping.exists?(area:)
      end
    end

    expect(adapter.resolve(area)).to eq(concurrent)
  end

  it 'keeps a colliding legacy Visit without a Place when resolving lazily' do
    started_at = Time.zone.parse('2026-05-01 10:00:00')
    area = create(:area, user:, name: 'Home')
    place = create(:place, user:, name: 'Home', latitude: area.latitude, longitude: area.longitude)
    canonical = create(:visit, user:, area: nil, place:, started_at:, ended_at: started_at + 1.hour)
    legacy = create(:visit, user:, area:, place: nil, started_at:, ended_at: started_at + 30.minutes)

    expect { adapter.resolve(area) }.not_to raise_error

    expect(canonical.reload.place).to eq(place)
    expect(legacy.reload).to have_attributes(place_id: nil, area_id: area.id)
  end

  it 'creates and updates the compatibility shell together with its Place' do
    area, place = adapter.create(name: 'Work', latitude: 52.5, longitude: 13.4, radius: 90)

    expect(place).to have_attributes(name: 'Work', visit_radius: 90)

    adapter.update(area, name: 'Office', latitude: 52.51, longitude: 13.41, radius: 120)

    expect(area.reload).to have_attributes(name: 'Office', radius: 120)
    expect(place.reload).to have_attributes(name: 'Office', visit_radius: 120)
  end

  it 'leaves Place fields a partial legacy update does not send' do
    area, place = adapter.create(name: 'Work', latitude: 52.5, longitude: 13.4, radius: 90)
    place.update!(latitude: 52.6, longitude: 13.5, visit_radius: 40)

    adapter.update(area, name: 'Office')

    expect(place.reload).to have_attributes(name: 'Office', visit_radius: 40)
    expect([place.lat, place.lon]).to eq([52.6, 13.5])
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

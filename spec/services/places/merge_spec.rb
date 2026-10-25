# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Places::Merge do
  let(:user) { create(:user) }
  let(:survivor) do
    create(
      :place,
      user:,
      name: 'Home',
      latitude: 52.52,
      longitude: 13.405,
      visit_radius: 80,
      note: 'Keep this',
      geodata: { 'properties' => { 'osm_id' => 1 } }
    )
  end
  let(:duplicate) do
    create(
      :place,
      user:,
      name: 'My home',
      latitude: 52.521,
      longitude: 13.406,
      visit_radius: 200,
      note: 'Also keep this',
      geodata: { 'external_place_id' => 'poi-2', 'properties' => { 'city' => 'Berlin' } }
    )
  end

  it 'moves confirmed and Suggested Visits without changing their ownership state' do
    confirmed = create(:visit, user:, place: duplicate, status: :confirmed)
    suggested = create(:visit, user:, place: duplicate, status: :suggested)
    survivor

    visit_count = Visit.count
    expect { described_class.new(user:, survivor:, duplicate:).call }
      .to change(Place, :count).by(-1)
    expect(Visit.count).to eq(visit_count)

    expect(confirmed.reload).to have_attributes(place_id: survivor.id, status: 'confirmed')
    expect(suggested.reload).to have_attributes(place_id: survivor.id, status: 'suggested')
  end

  it 'unions tags, suggestions, legacy mappings, and notes' do
    survivor_tag = create(:tag, user:, name: 'Home')
    duplicate_tag = create(:tag, user:, name: 'Favorite')
    survivor.tags << survivor_tag
    duplicate.tags << duplicate_tag
    suggested_visit = create(:visit, user:)
    create(:place_visit, place: survivor, visit: suggested_visit)
    create(:place_visit, place: duplicate, visit: suggested_visit)
    area = create(:area, user:)
    mapping = LegacyAreaPlaceMapping.create!(area:, place: duplicate)
    noted_at = Time.zone.parse('2026-09-01 12:00')
    survivor.notes.create!(user:, noted_at:, body: 'First note')
    duplicate.notes.create!(user:, noted_at:, body: 'Second note')

    described_class.new(user:, survivor:, duplicate:).call

    expect(survivor.reload.tags).to contain_exactly(survivor_tag, duplicate_tag)
    expect(survivor.place_visits.where(visit: suggested_visit).count).to eq(1)
    expect(mapping.reload.place).to eq(survivor)
    expect(survivor.notes.find_by(noted_at:).body).to eq("First note\n\nSecond note")
    expect(survivor.note).to eq("Keep this\n\nAlso keep this")
  end

  it 'keeps a same-day note as a standalone note when the merged text would be too long' do
    noted_at = Time.zone.parse('2026-09-01 12:00')
    survivor_body = 'a' * 6_000
    duplicate_body = 'b' * 6_000
    survivor_note = survivor.notes.create!(user:, noted_at:, body: survivor_body)
    duplicate_note = duplicate.notes.create!(user:, noted_at:, body: duplicate_body)

    expect { described_class.new(user:, survivor:, duplicate:).call }.to change(Place, :count).by(-1)

    expect(survivor_note.reload.body).to eq(survivor_body)
    expect(duplicate_note.reload).to have_attributes(attachable: nil, body: duplicate_body)
  end

  it 'keeps the survivor geometry, name, and Visit Radius while filling missing geodata' do
    described_class.new(user:, survivor:, duplicate:).call

    expect(survivor.reload).to have_attributes(
      name: 'Home',
      latitude: 52.52,
      longitude: 13.405,
      visit_radius: 80
    )
    expect(survivor.geodata).to include('external_place_id' => 'poi-2')
    expect(survivor.geodata['properties']).to eq('city' => 'Berlin', 'osm_id' => 1)
  end

  it 'keeps a discovered survivor from orphan cleanup when the duplicate was user-curated' do
    discovered = create(:place, user:, source: :photon, note: nil)
    curated = create(:place, user:, source: :manual, note: nil)

    described_class.new(user:, survivor: discovered, duplicate: curated).call

    expect(discovered.reload).to be_name_locked
    expect(Places::DeleteIfOrphan.call(discovered.id)).to be(false)
    expect(Place.exists?(discovered.id)).to be(true)
  end

  it 'keeps a discovered survivor when the merged discovered duplicate was renamed' do
    discovered = create(:place, user:, source: :photon, note: nil)
    renamed = create(:place, user:, source: :photon, note: nil)
    renamed.update!(name: 'Grandma')

    described_class.new(user:, survivor: discovered, duplicate: renamed).call

    expect(discovered.reload).to have_attributes(source: 'manual', name_locked?: true)
  end

  it 'carries enter and leave notifications, their events and webhook filters to the survivor' do
    duplicate.update!(geofence: true)
    event = create(:geofence_event, user:, place: duplicate)
    webhook = create(:webhook, user:, place_ids: [duplicate.id])

    described_class.new(user:, survivor:, duplicate:).call

    expect(survivor.reload).to be_geofence
    expect(event.reload.place_id).to eq(survivor.id)
    expect(webhook.reload).to have_attributes(place_ids: [survivor.id], active: true)
  end

  it 'blocks a merge when Visit timestamps would collide' do
    started_at = Time.zone.parse('2026-09-01 12:00:00')
    survivor_visit = create(:visit, user:, place: survivor, started_at:)
    duplicate_visit = create(:visit, user:, place: duplicate, started_at:)

    visit_count = Visit.count
    expect do
      described_class.new(user:, survivor:, duplicate:).call
    end.to raise_error(Places::Merge::VisitConflict)

    expect(Visit.count).to eq(visit_count)
    expect(survivor_visit.reload.place).to eq(survivor)
    expect(duplicate_visit.reload.place).to eq(duplicate)
    expect(Place.exists?(duplicate.id)).to be(true)
  end

  it 'rejects Places belonging to another user' do
    other_place = create(:place, user: create(:user))

    expect do
      described_class.new(user:, survivor:, duplicate: other_place).call
    end.to raise_error(ActiveRecord::RecordNotFound)
  end
end

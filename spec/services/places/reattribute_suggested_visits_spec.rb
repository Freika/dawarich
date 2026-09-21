# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Places::ReattributeSuggestedVisits do
  let(:user) { create(:user) }
  let(:lat) { 52.52 }
  let(:lon) { 13.405 }

  def north(meters) = meters / 111_320.0

  def visit_at(distance, **attributes)
    visit = create(
      :visit,
      { user: user, place: nil, status: :suggested,
        detection_version: Visits::Detection::VERSION,
        started_at: 2.days.ago, ended_at: 2.days.ago + 1.hour, duration: 60 }.merge(attributes)
    )
    create(:point, user: user, visit: visit, latitude: lat + north(distance), longitude: lon,
                   lonlat: "POINT(#{lon} #{lat + north(distance)})")
    visit
  end

  it 'attributes an unplaced Suggested Visit inside a newly created Place' do
    visit = visit_at(20, location_label: 'Old address')
    place = create(:place, user: user, name: 'Cafe', latitude: lat, longitude: lon, visit_radius: 50)

    count = described_class.new(user: user, changed_place: place).call

    expect(count).to eq(1)
    expect(visit.reload).to have_attributes(place_id: place.id, location_label: 'Cafe')
  end

  it 'weights Visit points by accuracy like detection does' do
    visit = visit_at(20, location_label: 'Old address')
    Point.where(visit: visit).update_all(accuracy: 5)
    create(:point, user: user, visit: visit, accuracy: 500, latitude: lat + north(400), longitude: lon,
                   lonlat: "POINT(#{lon} #{lat + north(400)})")
    place = create(:place, user: user, name: 'Cafe', latitude: lat, longitude: lon, visit_radius: 50)

    described_class.new(user: user, changed_place: place).call

    expect(visit.reload).to have_attributes(place_id: place.id, location_label: 'Cafe')
  end

  it 'skips a legacy Place without lonlat, as detection does' do
    legacy = create(:place, user: user, name: 'Legacy', latitude: lat, longitude: lon, visit_radius: 50)
    legacy.update_column(:lonlat, nil)
    visit = visit_at(20, location_label: 'Old address')
    place = create(:place, user: user, name: 'Cafe', latitude: lat, longitude: lon, visit_radius: 50)

    described_class.new(user: user, changed_place: place).call

    expect(visit.reload.place_id).to eq(place.id)
  end

  it 'removes a stale association after a Place moves away' do
    place = create(:place, user: user, name: 'Cafe', latitude: lat, longitude: lon, visit_radius: 50)
    visit = visit_at(20, place: place, location_label: 'Cafe')
    place.update!(latitude: lat + north(500))

    described_class.new(user: user, changed_place: place).call

    expect(visit.reload).to have_attributes(place_id: nil, location_label: nil)
  end

  it 'replaces the association using radius, distance, then stable ID precedence' do
    broad = create(:place, user: user, name: 'Campus', latitude: lat, longitude: lon, visit_radius: 200)
    visit = visit_at(10, place: broad, location_label: broad.name)
    specific = create(:place, user: user, name: 'Cafe', latitude: lat, longitude: lon, visit_radius: 25)

    described_class.new(user: user, changed_place: specific).call

    expect(visit.reload).to have_attributes(place_id: specific.id, location_label: 'Cafe')
  end

  it 'does not alter Confirmed Visits' do
    original = create(:place, user: user, name: 'Original', latitude: lat, longitude: lon, visit_radius: 100)
    confirmed = visit_at(10, place: original, status: :confirmed, location_label: original.name)
    specific = create(:place, user: user, name: 'Specific', latitude: lat, longitude: lon, visit_radius: 20)

    expect do
      described_class.new(user: user, changed_place: specific).call
    end.not_to(change { confirmed.reload.attributes.slice('place_id', 'location_label') })
  end

  it 'does not overwrite a Visit the user confirms while reattribution runs' do
    original = create(:place, user: user, name: 'Original', latitude: lat, longitude: lon, visit_radius: 100)
    visit = visit_at(10, place: original, location_label: original.name)
    specific = create(:place, user: user, name: 'Specific', latitude: lat, longitude: lon, visit_radius: 20)
    allow(Place).to receive(:attribution_for).and_wrap_original do |method, *args, **kwargs|
      visit.update_columns(status: Visit.statuses[:confirmed])
      method.call(*args, **kwargs)
    end

    described_class.new(user: user, changed_place: specific).call

    expect(visit.reload).to have_attributes(status: 'confirmed', place_id: original.id, location_label: 'Original')
  end

  it 'does not alter imported or annotated Suggested Visits' do
    original = create(:place, user: user, name: 'Original', latitude: lat, longitude: lon, visit_radius: 100)
    imported = visit_at(10, place: original, import_id: 42, location_label: original.name)
    annotated = visit_at(10, place: original, location_label: original.name)
    create(:note, user: user, attachable: annotated)
    specific = create(:place, user: user, name: 'Specific', latitude: lat, longitude: lon, visit_radius: 20)

    expect do
      described_class.new(user: user, changed_place: specific).call
    end.not_to(
      change do
        [imported, annotated].map { |visit| visit.reload.attributes.slice('place_id', 'location_label') }
      end
    )
  end

  it 'only evaluates Visits with points near the changed Place' do
    straddling = visit_at(3_000, location_label: 'Far away')
    create(:point, user: user, visit: straddling, latitude: lat - north(3_000), longitude: lon,
                   lonlat: "POINT(#{lon} #{lat - north(3_000)})")
    place = create(:place, user: user, name: 'Cafe', latitude: lat, longitude: lon, visit_radius: 50)

    described_class.new(user: user, changed_place: place).call

    expect(straddling.reload.place_id).to be_nil
  end

  it 'does not touch a Suggested Visit outside the affected Place' do
    distant = create(:place, user: user, name: 'Distant', latitude: lat + north(1_000), longitude: lon)
    visit = visit_at(1_000, place: distant, location_label: distant.name)
    changed = create(:place, user: user, latitude: lat, longitude: lon, visit_radius: 50)

    expect do
      described_class.new(user: user, changed_place: changed).call
    end.not_to(change { visit.reload.attributes.slice('place_id', 'location_label') })
  end
end

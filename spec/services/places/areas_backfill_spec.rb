# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Places::AreasBackfill do
  subject(:backfill) { described_class.new(batch_size: 2, logger: Logger.new(nil)) }

  describe '#call' do
    it 'creates a Place and mapping for an unmatched Area' do
      area = create(:area, name: 'Home', radius: 125)

      report = backfill.call

      mapping = LegacyAreaPlaceMapping.find_by!(area: area)
      expect(mapping.place).to have_attributes(
        name: 'Home', latitude: area.latitude, longitude: area.longitude,
        visit_radius: 125, source: 'manual'
      )
      expect(mapping.place).to be_name_locked
      expect(report).to include(areas_scanned: 1, places_created: 1)
    end

    it 'maps a same-name Place within 50 meters and preserves the larger Area radius' do
      user = create(:user)
      place = create(:place, user: user, name: 'Home', visit_radius: 50)
      area = create(:area, user: user, name: ' home ', latitude: place.lat, longitude: place.lon, radius: 125)

      report = backfill.call

      expect(LegacyAreaPlaceMapping.find_by!(area: area).place).to eq(place)
      expect(place.reload.visit_radius).to eq(125)
      expect(report[:areas_mapped]).to eq(1)
    end

    it 'does not merge Places based on proximity alone' do
      user = create(:user)
      existing = create(:place, user: user, name: 'Cafe', latitude: 52.437, longitude: 13.539)
      area = create(:area, user: user, name: 'Office', latitude: 52.437, longitude: 13.539)

      backfill.call

      mapping = LegacyAreaPlaceMapping.find_by!(area: area)
      expect(mapping.place).not_to eq(existing)
      expect(mapping.place.name).to eq('Office')
    end

    it 'reports an ambiguous same-name match instead of guessing' do
      user = create(:user)
      area = create(:area, user: user, name: 'Home', latitude: 52.437, longitude: 13.539)
      create(:place, user: user, name: 'Home', latitude: 52.437, longitude: 13.539)
      create(:place, user: user, name: ' home ', latitude: 52.4371, longitude: 13.539)

      report = backfill.call

      expect(LegacyAreaPlaceMapping.find_by(area: area)).to be_nil
      expect(report[:ambiguous_area_ids]).to contain_exactly(area.id)
    end

    it 'moves Area notes to the mapped Place' do
      area = create(:area)
      note = create(:note, user: area.user, attachable: area)

      backfill.call

      expect(note.reload.attachable).to eq(LegacyAreaPlaceMapping.find_by!(area: area).place)
    end

    it 'creates a separate Place when merging would collide note dates' do
      user = create(:user)
      time = Time.zone.parse('2026-05-01 12:00:00')
      place = create(:place, user: user, name: 'Home', latitude: 52.437, longitude: 13.539)
      area = create(:area, user: user, name: 'Home', latitude: 52.437, longitude: 13.539)
      create(:note, user: user, attachable: place, noted_at: time, body: 'Place note')
      create(:note, user: user, attachable: area, noted_at: time, body: 'Area note')

      backfill.call

      expect(LegacyAreaPlaceMapping.find_by!(area: area).place).not_to eq(place)
    end

    it 'assigns the mapped Place to an Area-only Visit without deleting the Visit' do
      area = create(:area)
      visit = create(:visit, user: area.user, area: area, place: nil)

      expect { backfill.call }.not_to change(Visit, :count)

      expect(visit.reload.place).to eq(LegacyAreaPlaceMapping.find_by!(area: area).place)
      expect(visit.area_id).to be_nil
    end

    it 'keeps the existing Place for a dual-linked Confirmed Visit' do
      user = create(:user)
      area = create(:area, user: user)
      place = create(:place, user: user)
      visit = create(:visit, user: user, area: area, place: place, status: :confirmed)

      report = backfill.call

      expect(visit.reload.place).to eq(place)
      expect(visit.area_id).to be_nil
      expect(report[:dual_user_owned_visits_retained]).to eq(1)
    end

    it 'reattributes a dual-linked Suggested Visit to the smallest containing Place' do
      user = create(:user)
      area = create(:area, user: user, name: 'Campus', latitude: 52.437, longitude: 13.539, radius: 500)
      broad = create(:place, user: user, latitude: 52.437, longitude: 13.539, visit_radius: 300)
      specific = create(:place, user: user, latitude: 52.437, longitude: 13.539, visit_radius: 25)
      visit = create(:visit, user: user, area: area, place: broad, status: :suggested)

      backfill.call

      expect(visit.reload.place).to eq(specific)
      expect(visit.area_id).to be_nil
    end

    it 'copies labels, clears machine Suggested names, and keeps user-owned names' do
      user = create(:user)
      suggested = create(:visit, user: user, name: 'Detected address', status: :suggested, import_id: nil,
                                 detection_version: Visits::Detection::VERSION)
      confirmed = create(:visit, user: user, name: 'Dinner with Anna', status: :confirmed)
      imported = create(:visit, user: user, name: 'Imported stop', status: :suggested, import_id: 42)
      annotated = create(:visit, user: user, name: 'Named suggestion', status: :suggested, import_id: nil)
      create(:note, user: user, attachable: annotated)

      backfill.call

      expect(suggested.reload).to have_attributes(name: nil, location_label: 'Detected address')
      expect(confirmed.reload).to have_attributes(name: 'Dinner with Anna', location_label: 'Dinner with Anna')
      expect(imported.reload).to have_attributes(name: 'Imported stop', location_label: 'Imported stop')
      expect(annotated.reload).to have_attributes(name: 'Named suggestion', location_label: 'Named suggestion')
    end

    it 'is idempotent' do
      area = create(:area)
      visit = create(:visit, user: area.user, area: area, place: nil)

      backfill.call
      place_id = visit.reload.place_id

      expect { backfill.call }.not_to change(Place, :count)
      expect(visit.reload.place_id).to eq(place_id)
      expect(LegacyAreaPlaceMapping.where(area: area).count).to eq(1)
    end
  end
end

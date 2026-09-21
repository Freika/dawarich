# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Areas::RelabelVisitsJob do
  let(:user) { create(:user) }
  let(:lat0) { 51.3402 }
  let(:lon0) { 12.3712 }
  let(:area) { create(:area, user:, latitude: lat0, longitude: lon0, radius: 200, name: 'Home') }

  def north(meters) = meters / 111_320.0

  def point_backed_visit(lat, lon, **attributes)
    visit = create(:visit, { user:, place: nil, status: :suggested,
                             detection_version: Visits::Detection::VERSION,
                             started_at: 2.days.ago, ended_at: 2.days.ago + 1.hour }.merge(attributes))
    create(:point, user:, visit_id: visit.id, latitude: lat, longitude: lon, lonlat: "POINT(#{lon} #{lat})")
    visit
  end

  it 'forwards legacy Area attribution to its canonical Place' do
    inside = point_backed_visit(lat0 + north(50), lon0)
    outside = point_backed_visit(lat0 + north(900), lon0, started_at: 3.days.ago, ended_at: 3.days.ago + 1.hour)

    described_class.perform_now(area.id)

    place = LegacyAreaPlaceMapping.find_by!(area:).place
    expect(inside.reload).to have_attributes(place_id: place.id, area_id: nil, location_label: 'Home')
    expect(outside.reload).to have_attributes(place_id: nil, area_id: nil)
  end

  it 'migrates existing Area-only Visits without deleting them' do
    visit = create(:visit, user:, area:, place: nil)

    expect { described_class.perform_now(area.id) }.not_to change(Visit, :count)

    expect(visit.reload).to have_attributes(
      place_id: LegacyAreaPlaceMapping.find_by!(area:).place_id,
      area_id: nil,
      location_label: 'Home'
    )
  end

  it 'does not reattribute a Confirmed Visit' do
    existing = create(:place, user:, latitude: lat0, longitude: lon0, visit_radius: 50)
    confirmed = point_backed_visit(lat0, lon0, status: :confirmed, place: existing)

    described_class.perform_now(area.id)

    expect(confirmed.reload).to have_attributes(place_id: existing.id, area_id: nil)
  end

  it 'quietly skips a deleted Area' do
    expect { described_class.perform_now(-1) }.not_to raise_error
  end

  describe 'enqueueing from direct Area lifecycle writes' do
    it 'enqueues on create and geometry changes, but not on rename' do
      new_area = nil
      expect { new_area = create(:area, user:, latitude: lat0, longitude: lon0, radius: 100) }
        .to have_enqueued_job(described_class)

      expect { new_area.update!(radius: 250) }.to have_enqueued_job(described_class).with(new_area.id)
      expect { new_area.update!(name: 'Renamed') }.not_to have_enqueued_job(described_class)
    end
  end
end

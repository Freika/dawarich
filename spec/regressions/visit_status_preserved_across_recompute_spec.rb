# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Visit status is preserved across visit-recompute services' do
  let!(:user) { create(:user) }
  let(:visit_date) { DateTime.new(2026, 1, 1, 10, 0, 0, Time.zone.formatted_offset) }

  describe Areas::Visits::Create do
    let(:area) { create(:area, user:, latitude: 0, longitude: 0, radius: 100) }

    before do
      create(:point, user:, lonlat: 'POINT(0 0)', timestamp: visit_date)
      create(:point, user:, lonlat: 'POINT(0 0)', timestamp: visit_date + 10.minutes)
      create(:point, user:, lonlat: 'POINT(0 0)', timestamp: visit_date + 20.minutes)
    end

    it 'keeps a confirmed visit confirmed when the service runs again' do
      described_class.new(user, [area]).call
      visit = Visit.find_by!(area_id: area.id)
      visit.update!(status: :confirmed)

      described_class.new(user, [area]).call

      expect(visit.reload.status).to eq('confirmed')
    end

    it 'keeps a declined visit declined when the service runs again' do
      described_class.new(user, [area]).call
      visit = Visit.find_by!(area_id: area.id)
      visit.update!(status: :declined)

      described_class.new(user, [area]).call

      expect(visit.reload.status).to eq('declined')
    end

    it 'still creates new visits with status suggested' do
      described_class.new(user, [area]).call
      expect(Visit.find_by!(area_id: area.id).status).to eq('suggested')
    end

    it 'keeps a user-chosen visit name when the service runs again' do
      described_class.new(user, [area]).call
      visit = Visit.find_by!(area_id: area.id)
      visit.update!(status: :confirmed, name: 'Home sweet home')

      described_class.new(user, [area]).call

      expect(visit.reload.name).to eq('Home sweet home')
    end

    it 'still extends ended_at on existing visits when new points arrive' do
      described_class.new(user, [area]).call
      visit = Visit.find_by!(area_id: area.id)
      visit.update!(status: :confirmed)
      original_ended_at = visit.ended_at

      create(:point, user:, lonlat: 'POINT(0 0)', timestamp: visit_date + 25.minutes)

      described_class.new(user, [area]).call

      expect(visit.reload.ended_at).to be > original_ended_at
    end
  end

  describe Places::Visits::Create do
    let(:place) { create(:place, user:, latitude: 5, longitude: 5) }

    before do
      create(:point, user:, lonlat: 'POINT(5 5)', timestamp: visit_date)
      create(:point, user:, lonlat: 'POINT(5 5)', timestamp: visit_date + 10.minutes)
      create(:point, user:, lonlat: 'POINT(5 5)', timestamp: visit_date + 20.minutes)
    end

    it 'keeps a confirmed visit confirmed when the service runs again' do
      described_class.new(user, [place]).call
      visit = Visit.find_by!(place_id: place.id)
      visit.update!(status: :confirmed)

      described_class.new(user, [place]).call

      expect(visit.reload.status).to eq('confirmed')
    end

    it 'keeps a declined visit declined when the service runs again' do
      described_class.new(user, [place]).call
      visit = Visit.find_by!(place_id: place.id)
      visit.update!(status: :declined)

      described_class.new(user, [place]).call

      expect(visit.reload.status).to eq('declined')
    end

    it 'still creates new visits with status suggested' do
      described_class.new(user, [place]).call
      expect(Visit.find_by!(place_id: place.id).status).to eq('suggested')
    end

    it 'still extends ended_at on existing visits when new points arrive' do
      described_class.new(user, [place]).call
      visit = Visit.find_by!(place_id: place.id)
      visit.update!(status: :confirmed)
      original_ended_at = visit.ended_at

      create(:point, user:, lonlat: 'POINT(5 5)', timestamp: visit_date + 25.minutes)

      described_class.new(user, [place]).call

      expect(visit.reload.ended_at).to be > original_ended_at
    end
  end

  # Cross-type: area recompute must not steal a confirmed
  # place visit's points nor spawn a suggested area twin over the same spot.
  describe 'cross-type: area recompute over a confirmed place visit' do
    let(:area) { create(:area, user:, latitude: 0, longitude: 0, radius: 100) }
    let(:place) { create(:place, user:, latitude: 0, longitude: 0) }
    let!(:confirmed_place_visit) do
      create(:visit, user:, place:, area: nil, status: :confirmed,
                     started_at: visit_date, ended_at: visit_date + 20.minutes, duration: 20)
    end

    before do
      [visit_date, visit_date + 10.minutes, visit_date + 20.minutes].each do |ts|
        create(:point, user:, lonlat: 'POINT(0 0)', timestamp: ts, visit_id: confirmed_place_visit.id)
      end
    end

    it 'does not steal the place visit points and creates no suggested area twin' do
      expect { Areas::Visits::Create.new(user, [area]).call }
        .not_to change { confirmed_place_visit.reload.points.count }.from(3)

      expect(Visit.where(area_id: area.id).count).to eq(0)
      expect(user.visits.suggested.count).to eq(0)
    end
  end

  # Vice-versa: place recompute must not steal a confirmed area visit's points nor
  # spawn a suggested place twin over the same spot.
  describe 'cross-type: place recompute over a confirmed area visit' do
    let(:area) { create(:area, user:, latitude: 0, longitude: 0, radius: 100) }
    let(:place) { create(:place, user:, latitude: 0, longitude: 0) }
    let!(:confirmed_area_visit) do
      create(:visit, user:, area:, place: nil, status: :confirmed,
                     started_at: visit_date, ended_at: visit_date + 20.minutes, duration: 20)
    end

    before do
      [visit_date, visit_date + 10.minutes, visit_date + 20.minutes].each do |ts|
        create(:point, user:, lonlat: 'POINT(0 0)', timestamp: ts, visit_id: confirmed_area_visit.id)
      end
    end

    it 'does not steal the area visit points and creates no suggested place twin' do
      expect { Places::Visits::Create.new(user, [place]).call }
        .not_to change { confirmed_area_visit.reload.points.count }.from(3)

      expect(Visit.where(place_id: place.id).count).to eq(0)
      expect(user.visits.suggested.count).to eq(0)
    end
  end
end

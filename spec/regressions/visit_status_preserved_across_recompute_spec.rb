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
end

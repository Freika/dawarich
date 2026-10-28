# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'History redetection skips legacy points without coordinates', type: :job do
  let(:user) { create(:user, visits_redetected_at: nil) }
  let(:started_at) { Time.zone.parse('2026-01-05 09:00:00 UTC') }
  let(:area) do
    create(:area, user: user, name: 'Synthetic ocean area', latitude: -48.123, longitude: -137.456)
  end
  let(:legacy_visit) { create_legacy_visit(started_at) }
  let(:later_visit) { create_legacy_visit(started_at + 1.day) }

  before do
    allow(DawarichSettings).to receive_messages(reverse_geocoding_enabled?: false, store_geodata?: false)

    missing_coordinates = create_visit_point(legacy_visit, accuracy: 1000)
    missing_coordinates.update_columns(lonlat: nil)
    create_visit_point(later_visit)
  end

  def create_legacy_visit(time)
    create(:visit, user: user, area: area, status: :confirmed, confidence: nil,
                   started_at: time, ended_at: time + 1.hour, duration: 60)
  end

  def create_visit_point(visit, accuracy: 10, offset: 60)
    create(:point, user: user, visit: visit, lonlat: 'POINT(-137.456 -48.123)',
                   timestamp: visit.started_at.to_i + offset, accuracy: accuracy)
  end

  context 'when the legacy visit also has a point with coordinates' do
    before { create_visit_point(legacy_visit, offset: 120) }

    it 'scores only coordinate-bearing points and completes the remaining history' do
      expect { Visits::UserRedetectJob.perform_now(user.id) }.not_to raise_error

      expect(later_visit.reload.confidence).to be_present
      expect(legacy_visit.reload.confidence).to eq(later_visit.confidence)
      expect(legacy_visit.confidence_breakdown).to eq(later_visit.confidence_breakdown)
      expect(legacy_visit.status).to eq('confirmed')
      expect(user.reload.visits_redetected_at).to be_present
    end
  end

  context 'when the legacy visit has no points with coordinates' do
    it 'leaves it unscored and completes the remaining history' do
      expect { Visits::UserRedetectJob.perform_now(user.id) }.not_to raise_error

      expect(legacy_visit.reload.confidence).to be_nil
      expect(legacy_visit.status).to eq('confirmed')
      expect(later_visit.reload.confidence).to be_present
      expect(user.reload.visits_redetected_at).to be_present
    end
  end
end

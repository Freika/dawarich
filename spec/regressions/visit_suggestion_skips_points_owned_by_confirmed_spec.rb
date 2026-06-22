# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Visits::Creator do
  let(:user) { create(:user) }
  let(:point1) { create(:point, user: user) }
  let(:point2) { create(:point, user: user) }

  subject { described_class.new(user) }

  describe '#create_visits when the candidate points already belong to a confirmed visit' do
    let(:visit_data) do
      {
        start_time: 2.hours.ago.to_i,
        end_time: 1.hour.ago.to_i,
        duration: 60.minutes.to_i,
        center_lat: 40.7128,
        center_lon: -74.0060,
        radius: 50,
        suggested_name: 'Redetected Place',
        points: [point1, point2]
      }
    end

    let(:corrected_place) do
      create(:place, name: 'Corrected Address', user_id: nil,
                     latitude: 40.7128, longitude: -74.0300,
                     lonlat: 'POINT(-74.0300 40.7128)')
    end

    let!(:confirmed_visit) do
      create(:visit, user: user, place: corrected_place, area: nil, status: :confirmed,
                     started_at: 2.hours.ago, ended_at: 1.hour.ago, duration: 60)
    end

    before do
      [point1, point2].each { |p| p.update_column(:visit_id, confirmed_visit.id) }
    end

    it 'does not re-suggest a duplicate even though the corrected place moved far from the points' do
      created = subject.create_visits([visit_data])

      expect(created).to be_empty
      expect(user.visits.reload.count).to eq(1)
      expect(user.visits.suggested.count).to eq(0)
    end
  end

  describe '#create_visits when the candidate points are not owned by any visit' do
    let(:visit_data) do
      {
        start_time: 2.hours.ago.to_i,
        end_time: 1.hour.ago.to_i,
        duration: 60.minutes.to_i,
        center_lat: 40.7128,
        center_lon: -74.0060,
        radius: 50,
        suggested_name: 'Fresh Place',
        points: [point1, point2]
      }
    end

    it 'creates a suggestion through the normal distance path' do
      created = subject.create_visits([visit_data])

      expect(created.size).to eq(1)
      expect(user.visits.suggested.count).to eq(1)
    end
  end
end

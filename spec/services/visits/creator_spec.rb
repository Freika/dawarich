# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Visits::Creator do
  let(:user) { create(:user) }

  subject { described_class.new(user) }

  describe '#create_visits' do
    let(:point1) { create(:point, user: user) }
    let(:point2) { create(:point, user: user) }

    let(:visit_data) do
      {
        start_time: 1.hour.ago.to_i,
        end_time: 30.minutes.ago.to_i,
        duration: 30.minutes.to_i,
        center_lat: 40.7128,
        center_lon: -74.0060,
        radius: 50,
        suggested_name: 'Test Place',
        points: [point1, point2]
      }
    end

    context 'when matching an area' do
      let!(:area) { create(:area, user: user, latitude: 40.7128, longitude: -74.0060, radius: 100) }

      before do
        allow(subject).to receive(:near_area?).and_return(true)
      end

      it 'creates a visit associated with the area' do
        visits = subject.create_visits([visit_data])

        expect(visits.size).to eq(1)
        visit = visits.first

        expect(visit.area).to eq(area)
        expect(visit.place).to be_nil
        expect(visit.started_at).to be_within(1.second).of(Time.zone.at(visit_data[:start_time]))
        expect(visit.ended_at).to be_within(1.second).of(Time.zone.at(visit_data[:end_time]))
        expect(visit.duration).to eq(30)
        expect(visit.name).to eq(area.name)
        expect(visit.status).to eq('suggested')

        expect(point1.reload.visit_id).to eq(visit.id)
        expect(point2.reload.visit_id).to eq(visit.id)
      end
    end

    context 'when matching a place' do
      let(:place) { create(:place, latitude: 40.7128, longitude: -74.0060) }
      let(:place_finder) { instance_double(Visits::PlaceFinder) }

      before do
        allow(subject).to receive(:near_area?).and_return(false)
        allow(Visits::PlaceFinder).to receive(:new).with(user).and_return(place_finder)
        allow(place_finder).to receive(:find_or_create_place).and_return(place)
      end

      it 'creates a visit associated with the place' do
        visits = subject.create_visits([visit_data])

        expect(visits.size).to eq(1)
        visit = visits.first

        expect(visit.area).to be_nil
        expect(visit.place).to eq(place)
        expect(visit.name).to eq(place.name)
      end
    end
  end
end

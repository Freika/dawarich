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

    context 'when a confirmed visit already exists at the same location' do
      let(:place) do
        create(:place, lonlat: 'POINT(-74.0060 40.7128)', name: 'Existing Place',
                      latitude: 40.7128, longitude: -74.0060, user_id: nil)
      end
      let!(:existing_visit) do
        create(
          :visit,
          user: user,
          place: place,
          area: nil,
          status: :confirmed,
          started_at: 1.5.hours.ago,
          ended_at: 45.minutes.ago,
          duration: 45
        )
      end

      it 'returns the existing confirmed visit instead of creating a duplicate suggested visit' do
        visits = subject.create_visits([visit_data])

        expect(visits).to be_empty

        # Verify no new visits were created
        expect(user.visits.reload.count).to eq(1)
      end

      it 'does not change points associations' do
        original_visit_id = point1.visit_id

        subject.create_visits([visit_data])

        # Points should remain unassociated
        expect(point1.reload.visit_id).to eq(original_visit_id)
        expect(point2.reload.visit_id).to eq(nil)
      end
    end

    context 'when an existing visit fully contains the candidate interval' do
      let(:visit_data) do
        {
          start_time: 4.hours.ago.to_i,
          end_time: 3.hours.ago.to_i,
          duration: 60.minutes.to_i,
          center_lat: 40.7128,
          center_lon: -74.0060,
          radius: 50,
          suggested_name: 'Contained Visit',
          points: [point1, point2]
        }
      end
      let(:place) do
        create(
          :place,
          lonlat: 'POINT(-74.0060 40.7128)', name: 'Existing Place',
          latitude: 40.7128, longitude: -74.0060, user_id: nil
        )
      end
      let!(:existing_visit) do
        create(
          :visit,
          user: user,
          place: place,
          area: nil,
          status: :confirmed,
          started_at: 6.hours.ago,
          ended_at: 1.hour.ago,
          duration: 300
        )
      end

      it 'does not create a duplicate when existing visit overlaps by containment' do
        visits = subject.create_visits([visit_data])

        expect(visits).to be_empty
        expect(user.visits.reload.count).to eq(1)
      end
    end

    context 'when a suggested visit already exists at the same location' do
      let(:place) do
        create(
          :place,
          lonlat: 'POINT(-74.0060 40.7128)', name: 'Existing Place',
          latitude: 40.7128, longitude: -74.0060, user_id: nil
        )
      end
      let!(:existing_visit) do
        create(
          :visit,
          user: user,
          place: place,
          area: nil,
          status: :suggested,
          started_at: 1.5.hours.ago,
          ended_at: 45.minutes.ago,
          duration: 45
        )
      end

      it 'returns the existing suggested visit instead of creating a duplicate' do
        visits = subject.create_visits([visit_data])

        expect(visits).to be_empty

        # Verify no new visits were created
        expect(user.visits.reload.count).to eq(1)
      end
    end

    context 'when a declined visit already exists at the same location' do
      let(:place) do
        create(
          :place,
          lonlat: 'POINT(-74.0060 40.7128)', name: 'Existing Place',
          latitude: 40.7128, longitude: -74.0060, user_id: nil
        )
      end
      let!(:existing_visit) do
        create(
          :visit,
          user: user,
          place: place,
          area: nil,
          status: :declined,
          started_at: 1.5.hours.ago,
          ended_at: 45.minutes.ago,
          duration: 45
        )
      end

      it 'returns the existing declined visit instead of creating a duplicate' do
        visits = subject.create_visits([visit_data])

        expect(visits).to be_empty

        # Verify no new visits were created
        expect(user.visits.reload.count).to eq(1)
      end
    end

    # Not 100% sure why a visit exists without place or area, but it is possible (verified in author's DB)
    context 'when a confirmed visit without place/area exists at the same location' do
      let!(:existing_visit) do
        create(
          :visit,
          user: user,
          place: nil,
          area: nil,
          status: :confirmed,
          started_at: 1.5.hours.ago,
          ended_at: 45.minutes.ago,
          duration: 45
        )
      end

      # Mock center_from_points since the visit has no points/place/area
      before do
        allow_any_instance_of(Visit).to receive(:center).and_return([40.7128, -74.0060])
      end

      it 'returns the existing confirmed visit' do
        visits = subject.create_visits([visit_data])

        expect(visits).to be_empty
      end
    end

    context 'when an existing visit has both area and place, area takes precedence' do
      let(:place) do
        create(
          :place,
          lonlat: 'POINT(-74.0060 40.7128)',
          name: 'New York Place',
          latitude: 40.7128,
          longitude: -74.0060,
          user_id: nil
        )
      end
      let(:area) do # Berlin
        create(
          :area,
          user: user,
          latitude: 52.5200,
          longitude: 13.4050,
          radius: 100
        )
      end
      let!(:existing_visit) do
        create(
          :visit,
          user: user,
          place: place,
          area: area,
          status: :confirmed,
          started_at: 1.5.hours.ago,
          ended_at: 45.minutes.ago,
          duration: 45
        )
      end
      let(:place_finder) { instance_double(Visits::PlaceFinder) }

      before do
        allow(Visits::PlaceFinder).to receive(:new).with(user).and_return(place_finder)
        allow(place_finder).to receive(:find_or_create_place).and_return(place)
      end

      it 'creates a new visit because existing visit location is determined by area (far away)' do
        # Existing visit has place at New York (match) but area at Berlin (mismatch).
        # Since area takes precedence, existing visit is considered at Berlin.
        # So it should NOT be detected as a duplicate of the new visit at New York.

        visits = subject.create_visits([visit_data])

        expect(visits.size).to eq(1)
        expect(visits.first.place).to eq(place)
        expect(user.visits.reload.count).to eq(2)
      end
    end

    context 'when a confirmed visit exists but at a different location' do
      let(:different_place) do
        create(:place, lonlat: 'POINT(-73.9000 41.0000)', name: 'Different Place', latitude: 41.0000,
longitude: -73.9000)
      end
      let!(:existing_visit) do
        create(
          :visit,
          user: user,
          place: different_place,
          status: :confirmed,
          started_at: 1.5.hours.ago,
          ended_at: 45.minutes.ago,
          duration: 45
        )
      end
      let(:place) do
        create(:place, lonlat: 'POINT(-74.0060 40.7128)', name: 'New Place', latitude: 40.7128, longitude: -74.0060)
      end
      let(:place_finder) { instance_double(Visits::PlaceFinder) }

      before do
        allow(Visits::PlaceFinder).to receive(:new).with(user).and_return(place_finder)
        allow(place_finder).to receive(:find_or_create_place).and_return(place)
      end

      it 'creates a new suggested visit' do
        visits = subject.create_visits([visit_data])

        expect(visits.size).to eq(1)
        expect(visits.first).not_to eq(existing_visit)
        expect(visits.first.place).to eq(place)
        expect(visits.first.status).to eq('suggested')

        # Should now have two visits
        expect(user.visits.reload.count).to eq(2)
      end
    end

    context 'when matching an area' do
      let!(:area) { create(:area, user: user, latitude: 40.7128, longitude: -74.0060, radius: 100) }

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

      it 'uses area name for visit name' do
        area.update(name: 'Custom Area Name')
        visits = subject.create_visits([visit_data])

        expect(visits.first.name).to eq('Custom Area Name')
      end

      it 'does not find areas too far from the visit center' do
        far_area = create(:area, user: user, latitude: 41.8781, longitude: -87.6298, radius: 100) # Chicago

        visits = subject.create_visits([visit_data])

        expect(visits.first.area).to eq(area) # Should match the closer area
        expect(visits.first.area).not_to eq(far_area)
      end
    end

    context 'when matching a place' do
      let(:place) { create(:place, name: 'Test Place') }
      let(:place_finder) { instance_double(Visits::PlaceFinder) }

      before do
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

    context 'when no area or place is found' do
      let(:place_finder) { instance_double(Visits::PlaceFinder) }

      before do
        allow(Visits::PlaceFinder).to receive(:new).with(user).and_return(place_finder)
        allow(place_finder).to receive(:find_or_create_place).and_return(nil)
      end

      it 'uses suggested name from visit data' do
        visits = subject.create_visits([visit_data])

        expect(visits.first.area).to be_nil
        expect(visits.first.place).to be_nil
        expect(visits.first.name).to eq('Test Place')
      end

      it 'uses "Unknown Location" when no name is available' do
        visit_data_without_name = visit_data.dup
        visit_data_without_name[:suggested_name] = nil

        visits = subject.create_visits([visit_data_without_name])

        expect(visits.first.name).to eq('Unknown Location')
      end
    end

    context 'when processing multiple visits' do
      let(:place1) { create(:place, name: 'Place 1') }
      let(:place2) { create(:place, name: 'Place 2') }
      let(:place_finder) { instance_double(Visits::PlaceFinder) }

      let(:visit_data2) do
        {
          start_time: 3.hours.ago.to_i,
          end_time: 2.hours.ago.to_i,
          duration: 60.minutes.to_i,
          center_lat: 41.8781,
          center_lon: -87.6298,
          radius: 50,
          suggested_name: 'Chicago Visit',
          points: [create(:point, user: user), create(:point, user: user)]
        }
      end

      before do
        allow(Visits::PlaceFinder).to receive(:new).with(user).and_return(place_finder)
        allow(place_finder).to receive(:find_or_create_place).with(visit_data).and_return(place1)
        allow(place_finder).to receive(:find_or_create_place).with(visit_data2).and_return(place2)
      end

      it 'creates multiple visits' do
        visits = subject.create_visits([visit_data, visit_data2])

        expect(visits.size).to eq(2)
        expect(visits[0].place).to eq(place1)
        expect(visits[0].name).to eq('Place 1')
        expect(visits[1].place).to eq(place2)
        expect(visits[1].name).to eq('Place 2')
      end
    end

    context 'when transaction fails' do
      let(:place_finder) { instance_double(Visits::PlaceFinder) }

      before do
        allow(Visits::PlaceFinder).to receive(:new).with(user).and_return(place_finder)
        allow(place_finder).to receive(:find_or_create_place).and_return(nil)
        allow(Visit).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)
      end

      it 'does not update points if visit creation fails' do
        expect do
          subject.create_visits([visit_data])
        end.to raise_error(ActiveRecord::RecordInvalid)

        # Points should not be associated with any visit
        expect(point1.reload.visit_id).to be_nil
        expect(point2.reload.visit_id).to be_nil
      end
    end

    context 'confidence scoring' do
      let(:point1) { create(:point, user: user, accuracy: 10) }
      let(:point2) { create(:point, user: user, accuracy: 12) }
      let(:place_finder) { instance_double(Visits::PlaceFinder) }

      before do
        allow(Visits::PlaceFinder).to receive(:new).with(user).and_return(place_finder)
        allow(place_finder).to receive(:find_or_create_place).and_return(nil)
      end

      it 'leaves confidence nil when scoring is off (default)' do
        visit = described_class.new(user).create_visits([visit_data]).first.reload

        expect(visit.confidence).to be_nil
        expect(visit.confidence_breakdown).to eq({})
      end

      it 'sets an integer confidence and a breakdown when scoring is on' do
        visit = described_class.new(user, scoring_on: true).create_visits([visit_data]).first.reload

        expect(visit.confidence).to be_between(0, 100)
        expect(visit.confidence_breakdown.keys).to include('dwell', 'tightness', 'density', 'accuracy')
      end
    end
  end

  describe '#find_matching_area' do
    let(:visit_data) do
      {
        center_lat: 40.7128,
        center_lon: -74.0060,
        radius: 50
      }
    end

    it 'finds areas within radius' do
      area_within = create(:area, user: user, latitude: 40.7129, longitude: -74.0061, radius: 100)
      create(:area, user: user, latitude: 40.7500, longitude: -74.0500, radius: 100)

      result = subject.send(:find_matching_area, visit_data)
      expect(result).to eq(area_within)
    end

    it 'returns nil when no areas match' do
      create(:area, user: user, latitude: 42.0, longitude: -72.0, radius: 100)

      result = subject.send(:find_matching_area, visit_data)
      expect(result).to be_nil
    end

    it 'only considers user areas' do
      create(:area, latitude: 40.7128, longitude: -74.0060, radius: 100)
      area_user = create(:area, user: user, latitude: 40.7128, longitude: -74.0060, radius: 100)

      result = subject.send(:find_matching_area, visit_data)
      expect(result).to eq(area_user)
    end
  end

  describe '#near_area?' do
    it 'returns true when point is within area radius' do
      area = create(:area, latitude: 40.7128, longitude: -74.0060, radius: 100)
      center = [40.7129, -74.0061] # Very close to area center

      result = subject.send(:near_area?, center, area)
      expect(result).to be true
    end

    it 'returns false when point is outside area radius' do
      area = create(:area, latitude: 40.7128, longitude: -74.0060, radius: 100)
      center = [40.7500, -74.0500] # Further away

      result = subject.send(:near_area?, center, area)
      expect(result).to be false
    end
  end

  describe 'no PlaceVisit fan-out' do
    let(:user) { create(:user) }

    it 'creates exactly one Place per detected visit (no PlaceVisit rows)' do
      allow(Places::NameFetcher).to receive(:lookup_attrs).and_return(
        { name: 'Café Bravo', city: 'Berlin', country: 'Germany', geodata: {} }
      )
      points = [create(:point, user: user, timestamp: 1.hour.ago.to_i)]
      visit_data = [{
        center_lat: 52.5126, center_lon: 13.4012,
        suggested_name: nil, points: points,
        start_time: 1.hour.ago.to_i, end_time: Time.current.to_i, duration: 3600
      }]

      expect { described_class.new(user).create_visits(visit_data) }
        .to change { Place.count }.by(1)
        .and change { PlaceVisit.count }.by(0)
    end
  end
end

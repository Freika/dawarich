# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Areas::Visits::Create do
  describe '#call' do
    let!(:user) { create(:user) }
    let(:home_area) { create(:area, user:, latitude: 0, longitude: 0, radius: 100) }
    let(:work_area) { create(:area, user:, latitude: 1, longitude: 1, radius: 100) }

    subject(:create_visits) { described_class.new(user, [home_area, work_area]).call }

    context 'when there are no points' do
      it 'does not create visits' do
        expect { create_visits }.not_to(change { Visit.count })
      end

      it 'does not log any visits' do
        expect(Rails.logger).not_to receive(:info)
        create_visits
      end
    end

    context 'when there are points' do
      let(:home_visit_date) { DateTime.new(2021, 1, 1, 10, 0, 0, Time.zone.formatted_offset) }
      let!(:home_point1) { create(:point, user:, lonlat: 'POINT(0 0)', timestamp: home_visit_date) }
      let!(:home_point2) { create(:point, user:, lonlat: 'POINT(0 0)', timestamp: home_visit_date + 10.minutes) }
      let!(:home_point3) { create(:point, user:, lonlat: 'POINT(0 0)', timestamp: home_visit_date + 20.minutes) }

      let(:work_visit_date) { DateTime.new(2021, 1, 1, 12, 0, 0, Time.zone.formatted_offset) }
      let!(:work_point1) { create(:point, user:, lonlat: 'POINT(1 1)', timestamp: work_visit_date) }
      let!(:work_point2) { create(:point, user:, lonlat: 'POINT(1 1)', timestamp: work_visit_date + 10.minutes) }
      let!(:work_point3) { create(:point, user:, lonlat: 'POINT(1 1)', timestamp: work_visit_date + 20.minutes) }

      it 'creates visits' do
        expect { create_visits }.to change { Visit.count }.by(2)
      end

      it 'creates visits with correct points' do
        create_visits

        home_visit = Visit.find_by(area_id: home_area.id)
        work_visit = Visit.find_by(area_id: work_area.id)

        expect(home_visit.points).to match_array([home_point1, home_point2, home_point3])
        expect(work_visit.points).to match_array([work_point1, work_point2, work_point3])
      end

      context 'when there are points outside the time threshold' do
        let(:home_point4) { create(:point, user:, lonlat: 'POINT(0 0)', timestamp: home_visit_date + 40.minutes) }

        it 'does not create visits' do
          expect { create_visits }.to change { Visit.count }.by(2)
        end

        it 'does not include points outside the time threshold' do
          create_visits

          home_visit = Visit.find_by(area_id: home_area.id)
          work_visit = Visit.find_by(area_id: work_area.id)

          expect(home_visit.points).to match_array([home_point1, home_point2, home_point3])
          expect(work_visit.points).to match_array([work_point1, work_point2, work_point3])
        end
      end

      context 'when there are visits already' do
        let!(:home_visit) do
          create(:visit,
                 user:,
                 started_at: Time.zone.at(home_point1.timestamp),
                 name: 'Home',
                 area: home_area,
                 points: [home_point1, home_point2])
        end
        let!(:work_visit) do
          create(:visit,
                 user:,
                 started_at: Time.zone.at(work_point1.timestamp),
                 name: 'Work',
                 area: work_area,
                 points: [work_point1, work_point2])
        end

        it 'does not create new visits' do
          expect { create_visits }.not_to(change { Visit.count })
        end

        it 'updates existing visits' do
          create_visits

          home_visit = Visit.find_by(area_id: home_area.id)
          work_visit = Visit.find_by(area_id: work_area.id)

          expect(home_visit.points).to match_array([home_point1, home_point2, home_point3])
          expect(work_visit.points).to match_array([work_point1, work_point2, work_point3])
        end
      end

      context 'running twice' do
        it 'does not create duplicate visits' do
          create_visits

          expect { create_visits }.not_to(change { Visit.count })
        end
      end
    end
  end
end

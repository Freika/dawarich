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

      it 'returns area points ordered by timestamp' do
        # We rely on this ordering to skip extra in-memory sorting in Visits::Group (see #2119)
        service = described_class.new(user, [home_area])

        points = service.send(:area_points_for_month, home_area, '2021-01')
        timestamps = points.map(&:timestamp)

        expect(timestamps).to eq(timestamps.sort)
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

      # Nightly job must not un-merge confirmed visits.
      context 'when a confirmed visit spans points across a grouping gap (e.g. after a manual merge)' do
        # Two clusters 3h apart, so Visits::Group re-splits them.
        let(:cluster_a_start) { home_visit_date + 3.hours }
        let(:cluster_b_start) { home_visit_date + 6.hours }
        let!(:cluster_a1) { create(:point, user:, lonlat: 'POINT(0 0)', timestamp: cluster_a_start) }
        let!(:cluster_a2) { create(:point, user:, lonlat: 'POINT(0 0)', timestamp: cluster_a_start + 15.minutes) }
        let!(:cluster_b1) { create(:point, user:, lonlat: 'POINT(0 0)', timestamp: cluster_b_start) }
        let!(:cluster_b2) { create(:point, user:, lonlat: 'POINT(0 0)', timestamp: cluster_b_start + 15.minutes) }

        let(:merged_points) { [cluster_a1, cluster_a2, cluster_b1, cluster_b2] }

        let!(:confirmed_home_visit) do
          create(:visit,
                 user:,
                 status: :confirmed,
                 started_at: Time.zone.at(cluster_a1.timestamp),
                 name: 'Home',
                 area: home_area,
                 points: merged_points)
        end

        it 'does not steal the later-cluster points into a new suggested visit' do
          described_class.new(user, [home_area]).call

          expect(cluster_b1.reload.visit_id).to eq(confirmed_home_visit.id)
          expect(cluster_b2.reload.visit_id).to eq(confirmed_home_visit.id)
        end

        it 'leaves the confirmed visit and its points intact' do
          described_class.new(user, [home_area]).call

          expect(confirmed_home_visit.reload.status).to eq('confirmed')
          expect(confirmed_home_visit.points).to match_array(merged_points)
        end
      end
    end
  end
end

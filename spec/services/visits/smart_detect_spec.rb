# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Visits::SmartDetect do
  let(:user) { create(:user) }
  let(:start_at) { 1.day.ago }
  let(:end_at) { Time.current }

  subject { described_class.new(user, start_at: start_at, end_at: end_at) }

  describe '#call' do
    context 'when there are no points' do
      it 'returns an empty array' do
        expect(subject.call).to eq([])
      end
    end

    context 'when there are points' do
      let!(:points) do
        create_list(:point, 5, user: user, timestamp: 2.hours.ago, visit_id: nil, anomaly: false)
      end
      let(:potential_visits) { [{ id: 1, center_lat: 40.7128, center_lon: -74.0060 }] }
      let(:merged_visits) { [{ id: 2, center_lat: 40.7128, center_lon: -74.0060 }] }
      let(:created_visits) { [instance_double(Visit)] }

      before do
        allow(Visits::Detector).to receive(:new).and_return(
          instance_double(Visits::Detector, detect_potential_visits: potential_visits)
        )
        allow(Visits::Merger).to receive(:new).and_return(
          instance_double(Visits::Merger, merge_visits: merged_visits)
        )
        allow(Visits::Creator).to receive(:new).with(user).and_return(
          instance_double(Visits::Creator, create_visits: created_visits)
        )
      end

      it 'delegates to the appropriate services and returns created visits' do
        expect(subject.call).to eq(created_visits)
      end
    end

    context 'when user is on Lite plan with points outside the 12-month window' do
      let!(:lite_user) do
        u = create(:user)
        u.update_columns(plan: User.plans[:lite])
        u
      end
      let(:archived_start) { 14.months.ago.beginning_of_day }
      let(:archived_end) { archived_start + 1.hour }

      before do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(false)

        # Old archived points (outside 12-month Lite window)
        15.times do |i|
          create(:point, :with_known_location, user: lite_user,
                                               timestamp: archived_start.to_i + (i * 5 * 60))
        end

        # Recent point (inside window)
        recent_ts = 1.day.ago.to_i
        create(:point, :with_known_location, user: lite_user, timestamp: recent_ts)
      end

      it 'exposes @points scoped to the plan window (excludes points older than 12 months)' do
        service = described_class.new(lite_user, start_at: archived_start, end_at: 1.hour.from_now)

        # Points older than the 12-month window must be filtered out via user.scoped_points
        archived_count = service.points.where(timestamp: archived_start.to_i..archived_end.to_i).count
        expect(archived_count).to eq(0)

        # Only the in-window point should remain
        expect(service.points.count).to eq(1)
      end
    end
  end
end

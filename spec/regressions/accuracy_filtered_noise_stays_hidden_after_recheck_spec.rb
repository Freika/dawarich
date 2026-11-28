# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Accuracy-filtered noise after an anomaly recheck', type: :job do
  let(:base_time) { Time.utc(2026, 1, 15, 12).to_i }

  # Made-up positions in the open Pacific. Precise fixes follow a straight
  # line; the intervening noise jumps about 550 m to alternating sides, too
  # slowly for any speed check to condemn it.
  def create_route(user, reported_velocity)
    [0, 0.005, 0, -0.005, 0].each_with_index.map do |latitude_offset, index|
      noisy = index.odd?
      create(:point, user: user, tracker_id: 'synthetic-phone',
                     timestamp: base_time + index * 300,
                     lonlat: "POINT(#{-140.0 + index * 0.0001} #{-40.0 + latitude_offset})",
                     accuracy: noisy ? 300 : 10,
                     velocity: noisy ? reported_velocity : '0',
                     vertical_accuracy: noisy ? -1 : 5,
                     anomaly: noisy)
    end
  end

  ['-1', '0'].each do |reported_velocity|
    context "with reported velocity #{reported_velocity} m/s and the accuracy threshold turned on" do
      let(:user) do
        create(:user, settings: { 'gps_filtering_enabled' => true,
                                  'gps_accuracy_filter_enabled' => true,
                                  'gps_accuracy_threshold' => 100 })
      end

      it 'keeps previously hidden sideways fixes out of the visible route' do
        points = create_route(user, reported_velocity)
        precise_points = points.values_at(0, 2, 4)
        noisy_points = points.values_at(1, 3)

        # The upgrade's backfill resets flags before applying the current rules.
        Points::AnomalyBackfillUserJob.perform_now(user.id, reset: true, notify: false)

        aggregate_failures do
          expect(noisy_points.map { |point| point.reload.anomaly }).to eq([true, true])
          expect(user.points.not_anomaly.order(:timestamp).pluck(:id)).to eq(precise_points.map(&:id))
        end
      end
    end
  end

  context 'with the accuracy threshold left off' do
    let(:user) { create(:user, settings: { 'gps_filtering_enabled' => true, 'gps_accuracy_threshold' => 100 }) }

    it 'shows coarse fixes again after the recheck' do
      points = create_route(user, '-1')

      Points::AnomalyBackfillUserJob.perform_now(user.id, reset: true, notify: false)

      expect(user.points.not_anomaly.order(:timestamp).pluck(:id)).to eq(points.map(&:id))
    end
  end
end

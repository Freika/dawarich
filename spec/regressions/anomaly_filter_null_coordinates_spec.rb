# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Anomaly filtering with missing coordinates' do
  let(:user) { create(:user) }
  let(:base_time) { Time.zone.local(2026, 6, 15).to_i }

  %i[main before after].each do |position|
    it "ignores missing coordinates in #{position} while detecting a displaced fix" do
      points = [0, 0.0001, 1, 0.0002, 0.0003].each_with_index.map do |offset, index|
        create(:point, user: user, latitude: 52.52 + offset, longitude: 13.405,
                       lonlat: "POINT(13.405 #{52.52 + offset})", timestamp: base_time + index * 60, accuracy: 10)
      end
      missing = create(:point, user: user, timestamp: base_time + 90, accuracy: 10)
      missing.update_columns(lonlat: nil)
      start_time, end_time = case position
                             when :before then [base_time + 120, base_time + 240]
                             when :after then [base_time, base_time + 60]
                             else [base_time, base_time + 240]
                             end

      expect(Points::AnomalyFilter.new(user.id, start_time, end_time).call).to eq(1)
      expect(points[2].reload.anomaly).to be(true) unless position == :after
      expect(missing.reload.anomaly).not_to be true
      expect(points.values_at(0, 3, 4).map { _1.reload.anomaly }).to all(be_falsey)
    end
  end
end

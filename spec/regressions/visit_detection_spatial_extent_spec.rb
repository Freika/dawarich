# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Visit detection spatial extent' do
  let(:user) do
    create(
      :user,
      settings: {
        'visit_radius_meters' => 100,
        'visit_min_points' => 3,
        'visit_min_duration_minutes' => 5,
        'time_threshold_minutes' => 30
      }
    )
  end

  let(:start_time) { Time.utc(2026, 6, 1, 12, 0, 0).to_i }

  it 'rejects slow moving clusters whose points span far beyond the visit radius' do
    create_path_points(count: 20, step_degrees: 0.00045)

    clusters = Visits::DbscanClusterer.new(user, start_at: start_time, end_at: start_time + 2.hours).call

    expect(clusters).to be_empty
  end

  it 'keeps compact stationary clusters within the visit radius' do
    create_path_points(count: 8, step_degrees: 0.00008)

    clusters = Visits::DbscanClusterer.new(user, start_at: start_time, end_at: start_time + 30.minutes).call

    expect(clusters.size).to eq(1)
    expect(clusters.first[:point_count]).to eq(8)
  end

  def create_path_points(count:, step_degrees:)
    count.times do |index|
      create(:point,
             user: user,
             longitude: index * step_degrees,
             latitude: 0,
             lonlat: "POINT(#{index * step_degrees} 0)",
             accuracy: 5,
             timestamp: start_time + (index * 60))
    end
  end
end

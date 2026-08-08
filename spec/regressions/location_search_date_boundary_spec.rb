# frozen_string_literal: true

require 'rails_helper'

# The container runs on UTC while the application zone does not, so for the
# hours between the two midnights a date means one day here and the previous
# day there. Every example below sits inside that window.
RSpec.describe LocationSearch::SpatialMatcher do
  include ActiveSupport::Testing::TimeHelpers

  let(:service) { described_class.new }
  let(:user) { create(:user) }
  let(:latitude) { 52.5200 }
  let(:longitude) { 13.4050 }

  around do |example|
    Time.use_zone('Europe/Berlin') do
      travel_to(Time.utc(2026, 8, 7, 23, 30)) { example.run }
    end
  end

  def point_at(time)
    create(:point, user: user, lonlat: 'POINT(13.4051 52.5201)', timestamp: time.to_i)
  end

  it 'starts the range at midnight in the application zone, not the container zone' do
    point = point_at(Time.current)

    results = service.find_points_near(user, latitude, longitude, 100, { date_from: Time.current.to_date })

    expect(results.map { |r| r[:id] }).to include(point.id)
  end

  it 'excludes a point that falls on the previous day in the application zone' do
    point = point_at(Time.current - 2.hours)

    results = service.find_points_near(user, latitude, longitude, 100, { date_from: Time.current.to_date })

    expect(results.map { |r| r[:id] }).not_to include(point.id)
  end

  it 'keeps the whole of the end date in range' do
    point = point_at(Time.current)

    results = service.find_points_near(user, latitude, longitude, 100, { date_to: Time.current.to_date })

    expect(results.map { |r| r[:id] }).to include(point.id)
  end
end

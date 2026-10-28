# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Android coarse location filtering' do
  let(:user) { create(:user) }
  let(:base_time) { 1.hour.ago.to_i }

  let!(:precise_points) do
    [0, 300].map do |offset|
      create(:point, user: user, tracker_id: 'android-phone', accuracy: 20,
                     velocity: '1.5', vertical_accuracy: 4, timestamp: base_time + offset,
                     lonlat: "POINT(13.405#{offset / 300} 52.520#{offset / 300})")
    end
  end

  let!(:coarse_points) do
    [
      [60, '0'],
      [120, '0.0'],
      [180, '00.00']
    ].map do |offset, velocity|
      create(:point, user: user, tracker_id: 'android-phone', accuracy: 600,
                     velocity: velocity, vertical_accuracy: 0, timestamp: base_time + offset,
                     lonlat: 'POINT(13.435 52.54)')
    end
  end

  let!(:coarse_singleton) do
    create(:point, user: user, tracker_id: 'android-phone', accuracy: 600,
                   velocity: '0', vertical_accuracy: 0, timestamp: base_time + 240,
                   lonlat: 'POINT(13.425 52.53)')
  end

  before { Points::AnomalyFilter.new(user.id, base_time, base_time + 300).call }

  it 'flags repeated coarse motionless fixes surrounded by precise fixes from the same device' do
    expect(coarse_points.map { |point| point.reload.anomaly }).to all(be(true))
    expect(precise_points.map { |point| point.reload.anomaly }).to all(be_falsey)
  end

  it 'keeps a single coarse point that may carry real route geometry' do
    expect(coarse_singleton.reload.anomaly).to be_falsey
  end
end

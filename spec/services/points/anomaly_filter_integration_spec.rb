# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'GPS Noise Filtering Integration' do
  let(:user) { create(:user) }

  describe 'full pipeline: points -> filter -> track exclusion' do
    let(:base_time) { 1.hour.ago.to_i }

    before do
      # Create 5 good walking points
      5.times do |i|
        create(:point, user: user,
               latitude: 52.52 + i * 0.0001,
               longitude: 13.405 + i * 0.0001,
               lonlat: "POINT(#{13.405 + i * 0.0001} #{52.52 + i * 0.0001})",
               timestamp: base_time + i * 60,
               accuracy: 10)
      end
      # 1 bad accuracy point
      create(:point, user: user,
             latitude: 52.53, longitude: 13.41,
             lonlat: 'POINT(13.41 52.53)',
             timestamp: base_time + 300,
             accuracy: 2000)

      Points::AnomalyFilter.new(user.id, base_time, base_time + 600).call
    end

    it 'marks bad accuracy points as anomalies' do
      expect(user.points.anomaly.count).to eq(1)
      expect(user.points.not_anomaly.count).to eq(5)
    end

    it 'excludes anomalies from track segmentation' do
      segments = Track.segment_points_in_sql(
        user.id, base_time, base_time + 600, 30, 500
      )
      all_ids = segments.flat_map { |s| s[:point_ids] }
      anomaly_ids = user.points.anomaly.pluck(:id)
      expect(all_ids & anomaly_ids).to be_empty
    end

    it 'excludes anomalies from not_anomaly scope' do
      expect(user.points.not_anomaly.pluck(:accuracy)).to all(be <= 100)
    end
  end

  describe 'speed-based anomaly detection' do
    let(:base_time) { 1.hour.ago.to_i }

    before do
      # Normal points
      [0, 60, 120, 180, 240].each_with_index do |offset, i|
        lat = 52.52 + i * 0.0001
        lon = 13.405 + i * 0.0001
        create(:point, user: user, latitude: lat, longitude: lon,
               lonlat: "POINT(#{lon} #{lat})",
               timestamp: base_time + offset, accuracy: 10)
      end
      # Teleportation spike at t+121
      create(:point, user: user, latitude: 62.52, longitude: 23.405,
             lonlat: 'POINT(23.405 62.52)',
             timestamp: base_time + 121, accuracy: 10)

      Points::AnomalyFilter.new(user.id, base_time, base_time + 300).call
    end

    it 'marks teleportation spike as anomaly' do
      spike = user.points.where(latitude: 62.52).first
      expect(spike.anomaly).to be true
    end

    it 'keeps normal points clean' do
      normal = user.points.where('latitude < 53')
      expect(normal.pluck(:anomaly).compact).to all(be false)
    end
  end
end

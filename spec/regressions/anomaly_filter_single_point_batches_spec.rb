# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Anomaly speed filter on points uploaded one per batch' do
  let(:user) { create(:user) }
  let(:base_time) { 30.minutes.ago.to_i }
  let(:base_lat) { 52.52 }
  let(:base_lon) { 13.405 }

  def ingest(lat_offset:, at:)
    lat = base_lat + lat_offset
    point = create(:point, user: user, latitude: lat, longitude: base_lon,
                           lonlat: "POINT(#{base_lon} #{lat})", timestamp: at, accuracy: 10)
    Points::AnomalyFilter.new(user.id, at, at).call
    point
  end

  let!(:first) { ingest(lat_offset: 0.0, at: base_time) }
  let!(:second) { ingest(lat_offset: 0.0001, at: base_time + 30) }
  let!(:displaced) { ingest(lat_offset: 0.087, at: base_time + 42) }

  it 'cannot judge the displaced fix before its successor arrives' do
    expect(displaced.reload.anomaly).not_to be true
  end

  context 'when the next fix arrives in its own batch' do
    let!(:next_fix) { ingest(lat_offset: 0.0002, at: base_time + 65) }

    it 'flags the displaced fix from the earlier batch' do
      expect(displaced.reload.anomaly).to be true
    end

    it 'leaves the ordinary fixes alone' do
      expect([first, second, next_fix].map { _1.reload.anomaly }).to all(be_falsey)
    end
  end
end

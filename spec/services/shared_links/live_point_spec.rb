# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SharedLinks::LivePoint do
  let(:user) { create(:user) }

  describe '#call' do
    it 'returns lat/lon/ts for a point outside any privacy zone' do
      result = described_class.new(user, lat: 60.0, lon: 10.0, timestamp: 1_700_000_000).call
      expect(result).to eq(lat: 60.0, lon: 10.0, ts: 1_700_000_000)
    end

    context 'with a privacy zone around (52.0, 13.0) of radius 500m' do
      let(:home) { create(:place, user: user, latitude: 52.0, longitude: 13.0) }
      let(:tag) { create(:tag, user: user, privacy_radius_meters: 500) }

      before { create(:tagging, tag: tag, taggable: home) }

      it 'masks a point at the zone centre' do
        result = described_class.new(user, lat: 52.0, lon: 13.0, timestamp: 1).call
        expect(result).to eq(masked: true)
      end

      it 'masks a point well inside the radius but not one well beyond it (boundary parity)' do
        inside  = described_class.new(user, lat: 52.0, lon: 13.003, timestamp: 1).call
        outside = described_class.new(user, lat: 52.0, lon: 13.010, timestamp: 1).call

        expect(inside).to eq(masked: true)
        expect(outside).to eq(lat: 52.0, lon: 13.010, ts: 1)
      end

      it 'matches the outside_privacy_zones SQL predicate for the same point (parity)' do
        lat = 52.0
        lon = 13.004
        point = create(:point, user: user, latitude: lat, longitude: lon, timestamp: 1)

        excluded_by_sql = user.points.where(
          'NOT ST_DWithin(lonlat, ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography, ?)',
          13.0, 52.0, 500
        ).exists?(point.id)

        masked = described_class.new(user, lat: lat, lon: lon, timestamp: 1).call == { masked: true }

        expect(masked).to eq(!excluded_by_sql)
      end
    end
  end
end

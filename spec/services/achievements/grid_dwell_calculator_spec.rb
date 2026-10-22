# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Achievements::GridDwellCalculator do
  let(:user) { create(:user) }
  let(:base_ts) { DateTime.new(2026, 1, 1).to_i }

  let(:per_point_sql) do
    <<~SQL
        WITH pts AS (
          SELECT p."timestamp" AS ts, m.code,
               LEAD(p."timestamp") OVER (ORDER BY p."timestamp", p.id) AS next_ts,
               LEAD(m.code) OVER (ORDER BY p."timestamp", p.id) AS next_code
        FROM points p
        LEFT JOIN LATERAL (
          SELECT r.code FROM regions r
          WHERE ST_Intersects(r.geom, p.lonlat::geometry) ORDER BY r.code LIMIT 1
        ) m ON TRUE
        WHERE p.user_id = %<user_id>d AND p.lonlat IS NOT NULL AND (p.anomaly IS DISTINCT FROM TRUE)
      )
        SELECT code, SUM(LEAST(next_ts - ts, 1800))::bigint
        FROM pts WHERE code IS NOT NULL AND code = next_code AND next_ts > ts GROUP BY code
    SQL
  end

  def per_point_dwell
    ApplicationRecord.connection
                     .select_rows(format(per_point_sql, user_id: user.id))
                     .to_h { |code, dwell| [code, dwell.to_i] }
  end

  before do
    create(:region, code: 'TT-01', geom: 'MULTIPOLYGON (((10 10, 10 12, 12 12, 12 10, 10 10)))')
    create(:region, code: 'TT-02', geom: 'MULTIPOLYGON (((20 20, 20 22, 22 22, 22 20, 20 20)))')
  end

  it 'matches an exact per-point lookup for points away from borders' do
    6.times { |i| create(:point, user:, longitude: 11.0, latitude: 11.0, timestamp: base_ts + (i * 600)) }
    6.times { |i| create(:point, user:, longitude: 21.0, latitude: 21.0, timestamp: base_ts + 20_000 + (i * 600)) }

    expect(described_class.new(user, table: 'regions').call).to eq(per_point_dwell)
  end

  it 'caps a single gap at the pair cap' do
    create(:point, user:, longitude: 11.0, latitude: 11.0, timestamp: base_ts)
    create(:point, user:, longitude: 11.0, latitude: 11.0, timestamp: base_ts + 7200)

    expect(described_class.new(user, table: 'regions').call['TT-01'])
      .to eq(described_class::PAIR_CAP_SECONDS)
  end

  it 'honours the since cursor' do
    6.times { |i| create(:point, user:, longitude: 11.0, latitude: 11.0, timestamp: base_ts + (i * 600)) }

    expect(described_class.new(user, table: 'regions', since: base_ts + 1800).call['TT-01']).to eq(1200)
  end

  it 'does not include points after the captured cursor' do
    6.times { |i| create(:point, user:, longitude: 11.0, latitude: 11.0, timestamp: base_ts + (i * 600)) }

    result = described_class.new(user, table: 'regions', through: base_ts + 1800).call

    expect(result['TT-01']).to eq(1800)
  end

  context 'with a disputed area over part of a region' do
    before { create(:disputed_area, geom: 'POLYGON ((10 10, 10 12, 11 12, 11 10, 10 10))') }

    it 'credits no region to points inside it' do
      6.times { |i| create(:point, user:, longitude: 10.5, latitude: 11.0, timestamp: base_ts + (i * 600)) }
      6.times { |i| create(:point, user:, longitude: 11.5, latitude: 11.0, timestamp: base_ts + 20_000 + (i * 600)) }

      expect(described_class.new(user, table: 'regions').call).to eq('TT-01' => 3000)
    end

    it 'does not bridge dwell across a stay inside it' do
      create(:point, user:, longitude: 11.5, latitude: 11.0, timestamp: base_ts)
      create(:point, user:, longitude: 10.5, latitude: 11.0, timestamp: base_ts + 600)
      create(:point, user:, longitude: 11.5, latitude: 11.0, timestamp: base_ts + 1200)

      expect(described_class.new(user, table: 'regions').call).to eq({})
    end

    it 'credits no region to a point inside it even when its cell centre lies outside' do
      create(:disputed_area, geom: 'POLYGON ((11.6 10, 11.6 12, 11.603 12, 11.603 10, 11.6 10))')
      6.times { |i| create(:point, user:, longitude: 11.601, latitude: 11.0, timestamp: base_ts + (i * 600)) }

      expect(described_class.new(user, table: 'regions').call).to eq({})
    end

    it 'dates the first visit from points outside it' do
      create(:point, user:, longitude: 10.5, latitude: 11.0, timestamp: base_ts)
      create(:point, user:, longitude: 11.5, latitude: 11.0, timestamp: base_ts + 600)

      expect(described_class.new(user, table: 'regions').first_seen).to eq('TT-01' => base_ts + 600)
    end
  end

  it 'rejects an unknown source table' do
    expect { described_class.new(user, table: 'users') }.to raise_error(ArgumentError, /unsupported source/)
  end
end

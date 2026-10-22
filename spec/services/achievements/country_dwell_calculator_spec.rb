# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Achievements::CountryDwellCalculator do
  let(:user) { create(:user) }
  let(:base_ts) { DateTime.new(2026, 1, 1).to_i }
  let(:country) { create(:country, name: 'Testland', iso_a2: 'TT', iso_a3: 'TST') }

  def track(longitude, from:, count: 6)
    count.times do |index|
      create(:point, user:, country:, longitude:, latitude: 11.0, timestamp: from + (index * 600))
    end
  end

  it 'does not include points after the captured cursor' do
    track(11.5, from: base_ts)

    result = described_class.new(user, through: base_ts + 1800).call

    expect(result['TT']).to eq(1800)
  end

  context 'with at least 90 percent country id coverage' do
    let!(:other_country) do
      create(:country, name: 'Otherland', iso_a2: 'UU', iso_a3: 'UUU',
                       geom: 'MULTIPOLYGON (((20 10, 20 12, 22 12, 22 10, 20 10)))')
    end

    def insert_points(country_ids:, longitude:, from:)
      Point.insert_all!(country_ids.each_with_index.map do |country_id, index|
        { user_id: user.id, country_id:, lonlat: "POINT(#{longitude} 11)",
          timestamp: from + index * 600, created_at: Time.current, updated_at: Time.current }
      end)
    end

    before { insert_points(country_ids: [country.id] * 18, longitude: 11.5, from: base_ts) }

    it 'credits and dates a country visited only by untagged points' do
      insert_points(country_ids: [nil, nil], longitude: 20.5, from: base_ts + 20_000)
      calculator = described_class.new(user)

      expect(calculator.call).to eq('TT' => 10_200, 'UU' => 600)
      expect(calculator.first_seen).to eq('TT' => base_ts, 'UU' => base_ts + 20_000)
      expect(described_class.new(user).first_seen).to eq(calculator.first_seen)
    end

    it 'counts the pair between tagged and untagged points in the same country once' do
      insert_points(country_ids: [nil, other_country.id], longitude: 20.5, from: base_ts + 20_000)
      calculator = described_class.new(user)

      expect(calculator.call).to eq('TT' => 10_200, 'UU' => 600)
      expect(calculator.first_seen['UU']).to eq(base_ts + 20_000)
    end

    it 'credits no country to untagged points outside every country' do
      insert_points(country_ids: [nil, nil], longitude: 30.5, from: base_ts + 20_000)
      calculator = described_class.new(user)

      expect(calculator.call).to eq('TT' => 10_200)
      expect(calculator.first_seen).to eq('TT' => base_ts)
    end

    it 'excludes untagged points inside disputed areas' do
      create(:disputed_area, geom: 'POLYGON ((20 10, 20 12, 21 12, 21 10, 20 10))')
      insert_points(country_ids: [nil, nil], longitude: 20.5, from: base_ts + 20_000)
      calculator = described_class.new(user)

      expect(calculator.call).to eq('TT' => 10_200)
      expect(calculator.first_seen).to eq('TT' => base_ts)
    end
  end

  context 'with a disputed area' do
    before { create(:disputed_area, geom: 'POLYGON ((10 10, 10 12, 11 12, 11 10, 10 10))') }

    it 'credits no country to points inside it, whatever country they were filed under' do
      track(10.5, from: base_ts)
      track(11.5, from: base_ts + 20_000)

      expect(described_class.new(user).call).to eq('TT' => 3000)
    end

    it 'does not bridge dwell across a stay inside it' do
      track(11.5, from: base_ts, count: 1)
      track(10.5, from: base_ts + 600, count: 1)
      track(11.5, from: base_ts + 1200, count: 1)

      expect(described_class.new(user).call).to eq({})
    end

    it 'keeps using country ids when every point lies inside it' do
      track(10.5, from: base_ts)

      calculator = described_class.new(user)

      expect(calculator.call).to eq({})
      expect(calculator.first_seen).to eq({})
    end

    it 'credits no country to a point inside it even when its grid cell centre lies outside' do
      create(:disputed_area, geom: 'POLYGON ((20 10, 20 12, 20.003 12, 20.003 10, 20 10))')
      track(20.001, from: base_ts)

      expect(described_class.new(user).call).to eq({})
    end

    it 'dates the first visit from points outside it' do
      track(10.5, from: base_ts, count: 1)
      track(11.5, from: base_ts + 600, count: 1)

      expect(described_class.new(user).first_seen).to eq('TT' => base_ts + 600)
    end
  end
end

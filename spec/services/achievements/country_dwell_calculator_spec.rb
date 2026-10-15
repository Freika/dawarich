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

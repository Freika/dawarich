# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Stats::Toponyms do
  it 'matches country-only presence without emitting unnamed cities at any stay threshold' do
    country = create(:country, name: 'Germany', iso_a2: 'DE', iso_a3: 'DEU')
    points = [
      { timestamp: 0, country_name: 'Deutschland', country_id: country.id, city: nil },
      { timestamp: 3600, country_name: 'Germany', city: '' },
      { timestamp: 7200, country_name: 'Germany', city: '  ' },
      { timestamp: 10_800, country_name: nil, city: 'Berlin' },
      { timestamp: 14_400, country_name: 'France', city: nil, velocity: 250 },
      { timestamp: 18_000, country_name: 'France', city: nil, velocity: 250 },
      { timestamp: 21_600, country_name: 'Belgium', city: nil, velocity: 500 / 3.6 }
    ]

    [0, 60, 240].each do |minimum|
      expected = [{ 'country' => 'Germany', 'cities' => [] }, { 'country' => 'Belgium', 'cities' => [] }]

      expect(described_class.new(points.each, min_minutes_spent_in_city: minimum).call.as_json).to eq(expected)
      expect(CountriesAndCities.new(points, min_minutes_spent_in_city: minimum).call.as_json).to eq(expected)
    end
  end

  it 'matches split named city runs around a country-only point' do
    points = [
      { timestamp: 0, country_name: 'Germany', city: 'Berlin' },
      { timestamp: 1800, country_name: 'Germany', city: 'Berlin' },
      { timestamp: 3600, country_name: 'Germany', city: nil },
      { timestamp: 5400, country_name: 'Germany', city: 'Berlin' },
      { timestamp: 7200, country_name: 'Germany', city: 'Berlin' }
    ]

    [60, 61].each do |minimum|
      cities = minimum == 60 ? [{ 'city' => 'Berlin', 'points' => 4, 'timestamp' => 7200, 'stayed_for' => 60 }] : []
      expected = [{ 'country' => 'Germany', 'cities' => cities }]

      expect(described_class.new(points.each, min_minutes_spent_in_city: minimum).call.as_json).to eq(expected)
      expect(CountriesAndCities.new(points, min_minutes_spent_in_city: minimum).call.as_json).to eq(expected)
    end
  end

  it 'matches existing dwell, flyover, gap, alias and city-count semantics on ordered traces' do
    country = create(:country, name: 'Germany', iso_a2: 'DE', iso_a3: 'DEU')
    random = Random.new(724)
    30.times do
      timestamp = Time.utc(2024, 1, 1).to_i
      points = 300.times.map do |id|
        timestamp += [0, 1, 600, 3600, 8.days.to_i].sample(random: random)
        { id: id, timestamp: timestamp, city: [nil, 'Berlin', 'London', ''].sample(random: random),
          country_name: [nil, 'Germany', 'Deutschland', 'UK'].sample(random: random),
          country_id: [nil, country.id].sample(random: random),
          velocity: [0, 5, 20, 150, 250].sample(random: random) }
      end
      [0, 60, 240].each do |minimum|
        expected = CountriesAndCities.new(points, min_minutes_spent_in_city: minimum).call.as_json
        actual = described_class.new(points.each, min_minutes_spent_in_city: minimum).call.as_json
        expect(actual).to eq(expected)
      end
    end
  end

  it 'preserves a stay across fetch boundaries without retaining the entire trace' do
    points = Enumerator.new do |stream|
      10_001.times do |id|
        stream << { id: id, timestamp: id * 60, city: 'Berlin', country_name: 'Germany', velocity: 0 }
      end
    end
    result = described_class.new(points, min_minutes_spent_in_city: 60).call.as_json
    expect(result.first['cities']).to eq([{ 'city' => 'Berlin', 'points' => 10_001,
                                           'timestamp' => 600_000, 'stayed_for' => 10_000 }])
  end
end

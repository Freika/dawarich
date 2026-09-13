# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Stats::Toponyms do
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

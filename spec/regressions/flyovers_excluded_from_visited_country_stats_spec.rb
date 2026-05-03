# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Flyovers excluded from visited-country statistics' do
  let(:user) { create(:user) }
  let(:year) { 2026 }
  let(:month) { 4 }
  let(:base_ts) { DateTime.new(year, month, 5, 12).to_i }
  let!(:import) { create(:import, user: user) }

  let!(:berlin_points) do
    [0, 30, 70, 90].map do |minute_offset|
      create(:point, user: user, import: import,
                     timestamp: base_ts + minute_offset.minutes,
                     city: 'Berlin', country_name: 'Germany',
                     altitude: 50, velocity: '5',
                     lonlat: 'POINT(13.404954 52.520008)')
    end
  end

  let!(:moscow_flyover_points) do
    flyover_start = base_ts + 6.hours.to_i
    (0..240).step(5).map do |minute_offset|
      create(:point, user: user, import: import,
                     timestamp: flyover_start + minute_offset.minutes,
                     city: 'Moscow', country_name: 'Russia',
                     altitude: 11_000, velocity: '250',
                     lonlat: 'POINT(37.6173 55.7558)')
    end
  end

  let!(:kazakhstan_flyover_points) do
    flyover_start = base_ts + 12.hours.to_i
    %w[Aktobe Kostanay Astana Karaganda Almaty].each_with_index.flat_map do |city, idx|
      (0..30).step(5).map do |minute_offset|
        create(:point, user: user, import: import,
                       timestamp: flyover_start + (idx * 35 + minute_offset).minutes,
                       city: city, country_name: 'Kazakhstan',
                       altitude: 11_500, velocity: '255',
                       lonlat: "POINT(#{60 + idx} #{50 + idx * 0.5})")
      end
    end
  end

  let!(:zero_altitude_flight_points) do
    flight_start = base_ts + 20.hours.to_i
    (0..240).step(5).map do |minute_offset|
      create(:point, user: user, import: import,
                     timestamp: flight_start + minute_offset.minutes,
                     city: 'Reykjavik', country_name: 'Iceland',
                     altitude: 0, velocity: '240',
                     lonlat: 'POINT(-21.9426 64.1466)')
    end
  end

  before { Stats::CalculateMonth.new(user.id, year, month).call }

  let(:stat) { user.stats.find_by(year: year, month: month) }
  let(:countries_with_validated_cities) do
    stat.toponyms
        .select { |t| t['cities'].is_a?(Array) && t['cities'].any? }
        .map { |t| t['country'] }
        .compact
        .sort
  end

  it 'records only the ground-stay country with validated cities' do
    expect(countries_with_validated_cities).to eq(['Germany'])
  end

  it 'reports a single visited country via StatsHelper' do
    helper_class = Class.new { include StatsHelper }
    expect(helper_class.new.countries_visited(stat)).to eq(1)
  end

  it 'reports a single visited country via Insights::YearTotalsCalculator' do
    stats = user.stats.where(year: year)
    result = Insights::YearTotalsCalculator.new(stats, distance_unit: 'km').call

    expect(result.countries_count).to eq(1)
    expect(result.countries_list).to eq(['Germany'])
  end
end

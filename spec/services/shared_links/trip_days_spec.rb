# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SharedLinks::TripDays do
  let(:user) { create(:user) }
  let(:trip) do
    create(:trip, user: user,
                  started_at: Time.utc(2025, 6, 14),
                  ended_at: Time.utc(2025, 6, 15, 23, 59, 59))
  end

  before do
    create(:point, user: user, timestamp: Time.utc(2025, 6, 14, 10, 0).to_i, latitude: 52.0, longitude: 13.0)
    create(:point, user: user, timestamp: Time.utc(2025, 6, 14, 12, 0).to_i, latitude: 52.5, longitude: 13.5)
    create(:point, user: user, timestamp: Time.utc(2025, 6, 15, 9, 0).to_i,  latitude: 53.0, longitude: 14.0)
  end

  it 'returns one row per calendar day in the trip range (owner timezone)' do
    rows = described_class.new(trip, timezone: 'Etc/UTC', unit: 'km').call
    expect(rows.map { |r| r[:date] }).to eq([Date.new(2025, 6, 14), Date.new(2025, 6, 15)])
  end

  it 'computes first/last time, distance and a stable color for days with points' do
    rows = described_class.new(trip, timezone: 'Etc/UTC', unit: 'km').call
    day1 = rows.first

    expect(day1[:has_data]).to be true
    expect(day1[:weekday]).to eq('Saturday')
    expect(day1[:first_time].strftime('%H:%M')).to eq('10:00')
    expect(day1[:last_time].strftime('%H:%M')).to eq('12:00')
    expect(day1[:distance_label]).to match(/\Akm\z|km\z/)
    expect(day1[:color]).to match(/\A#[0-9a-f]{6}\z/i)
  end

  it 'excludes points inside a privacy zone from day stats' do
    home = create(:place, user: user, latitude: 52.0, longitude: 13.0)
    tag = create(:tag, user: user, privacy_radius_meters: 500)
    create(:tagging, tag: tag, taggable: home)

    rows = described_class.new(trip, timezone: 'Etc/UTC', unit: 'km').call

    expect(rows.first[:first_time].strftime('%H:%M')).to eq('12:00')
  end

  it 'marks days without points as no-data' do
    other = create(:trip, user: user, started_at: Time.utc(2025, 7, 1), ended_at: Time.utc(2025, 7, 2, 23, 59))
    rows = described_class.new(other, timezone: 'Etc/UTC', unit: 'km').call

    expect(rows.size).to eq(2)
    expect(rows).to all(include(has_data: false))
    expect(rows.first[:first_time]).to be_nil
  end

  it 'converts distance to the requested unit' do
    km_rows = described_class.new(trip, timezone: 'Etc/UTC', unit: 'km').call
    mi_rows = described_class.new(trip, timezone: 'Etc/UTC', unit: 'mi').call

    expect(km_rows.first[:distance_label]).to include('km')
    expect(mi_rows.first[:distance_label]).to include('mi')
  end
end

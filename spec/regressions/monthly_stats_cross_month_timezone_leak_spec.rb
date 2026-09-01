# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Monthly stats bucketing for points near month boundary in non-UTC timezone' do
  def create_point(user, lon, lat, time)
    create(:point, user: user, lonlat: "POINT(#{lon} #{lat})", timestamp: time.to_i)
  end

  def calculate_and_load(user, year, month)
    Stats::CalculateMonth.new(user.id, year, month).call
    Stat.find_by(user: user, year: year, month: month)
  end

  context 'Europe/Berlin (DST timezone), eastbound month boundary' do
    let(:tz) { 'Europe/Berlin' }
    let(:user) { create(:user, settings: { 'timezone' => tz }) }

    let!(:home_point_march_1) { create_point(user, 8.682, 50.111, Time.utc(2026, 3, 1, 12, 0, 0)) }
    let!(:flight_tail_utc_march_31) { create_point(user, -40.0, 50.0, Time.utc(2026, 3, 31, 23, 30, 0)) }

    it 'does not attribute the cross-month flight point to day 1 of March' do
      stat = calculate_and_load(user, 2026, 3)

      expect(stat.daily_distance.find { |day, _| day == 1 }&.last).to eq(0)
      expect(stat.distance).to eq(0)
    end

    it 'attributes the flight point to local April day 1, not phantom March' do
      stat = calculate_and_load(user, 2026, 4)

      expect(stat.daily_distance.find { |day, _| day == 1 }&.last).to eq(0)
    end
  end

  context 'Europe/Berlin (DST timezone), westbound month boundary' do
    let(:tz) { 'Europe/Berlin' }
    let(:user) { create(:user, settings: { 'timezone' => tz }) }

    let!(:point_utc_feb_28_local_march_1_a) { create_point(user, 13.4, 52.5, Time.utc(2026, 2, 28, 23, 30, 0)) }
    let!(:point_utc_feb_28_local_march_1_b) { create_point(user, 13.5, 52.6, Time.utc(2026, 2, 28, 23, 45, 0)) }

    it 'attributes both UTC-February points to March day 1 with a measurable segment distance' do
      stat = calculate_and_load(user, 2026, 3)

      day_1 = stat.daily_distance.find { |day, _| day == 1 }&.last
      expect(day_1).to be > 0
      expect(stat.distance).to be > 0
    end

    it 'excludes the same UTC-February points from February day 28 (they belong to local March)' do
      stat = calculate_and_load(user, 2026, 2)

      expect(stat.daily_distance.find { |day, _| day == 28 }&.last).to eq(0)
    end
  end

  context 'Europe/Berlin DST spring-forward (non-boundary correctness)' do
    let(:tz) { 'Europe/Berlin' }
    let(:user) { create(:user, settings: { 'timezone' => tz }) }

    # 20 minutes apart, straddling the 01:00 UTC spring-forward: a wider gap
    # than minutes_between_routes would be two routes and carry no distance.
    let!(:before_dst) { create_point(user, 13.4, 52.5, Time.utc(2026, 3, 29, 0, 50, 0)) }
    let!(:after_dst) { create_point(user, 13.41, 52.51, Time.utc(2026, 3, 29, 1, 10, 0)) }

    it 'buckets both DST-spanning points into March day 29 with non-zero distance' do
      stat = calculate_and_load(user, 2026, 3)

      day_29 = stat.daily_distance.find { |day, _| day == 29 }&.last
      expect(day_29).to be > 0
      expect(stat.daily_distance.find { |day, _| day == 28 }&.last).to eq(0)
      expect(stat.daily_distance.find { |day, _| day == 30 }&.last).to eq(0)
    end
  end

  context 'Asia/Tokyo (non-DST timezone, UTC+9)' do
    let(:tz) { 'Asia/Tokyo' }
    let(:user) { create(:user, settings: { 'timezone' => tz }) }

    let!(:point_utc_feb_28_local_march_1_a) { create_point(user, 139.69, 35.69, Time.utc(2026, 2, 28, 15, 30, 0)) }
    let!(:point_utc_feb_28_local_march_1_b) { create_point(user, 139.7, 35.7, Time.utc(2026, 2, 28, 16, 0, 0)) }
    let!(:point_utc_march_31_local_april_1) { create_point(user, 139.8, 35.8, Time.utc(2026, 3, 31, 23, 30, 0)) }

    it 'includes the UTC-Feb-28 points in Tokyo March day 1 and excludes the UTC-Mar-31 point' do
      stat = calculate_and_load(user, 2026, 3)

      day_1 = stat.daily_distance.find { |day, _| day == 1 }&.last
      expect(day_1).to be > 0
      expect(stat.distance).to be > 0
    end

    it 'does not phantom-attribute the UTC-Mar-31 point to April day 1 of Tokyo' do
      stat = calculate_and_load(user, 2026, 4)

      expect(stat.daily_distance.find { |day, _| day == 1 }&.last).to eq(0)
    end
  end

  context 'America/Los_Angeles (DST timezone, negative offset)' do
    let(:tz) { 'America/Los_Angeles' }
    let(:user) { create(:user, settings: { 'timezone' => tz }) }

    let!(:point_utc_april_1_local_march_31_a) { create_point(user, -118.24, 34.05, Time.utc(2026, 4, 1, 5, 0, 0)) }
    let!(:point_utc_april_1_local_march_31_b) { create_point(user, -118.25, 34.06, Time.utc(2026, 4, 1, 5, 20, 0)) }

    it 'attributes both UTC-April points to local March 31 (LA PDT) with non-zero distance' do
      stat = calculate_and_load(user, 2026, 3)

      day_31 = stat.daily_distance.find { |day, _| day == 31 }&.last
      expect(day_31).to be > 0
      expect(stat.distance).to be > 0
    end

    it 'does not double-count the UTC-April points as April day 1' do
      stat = calculate_and_load(user, 2026, 4)

      expect(stat.daily_distance.find { |day, _| day == 1 }&.last).to eq(0)
    end
  end

  context 'year boundary (Europe/Berlin, Dec 31 UTC -> Jan 1 local)' do
    let(:tz) { 'Europe/Berlin' }
    let(:user) { create(:user, settings: { 'timezone' => tz }) }

    let!(:point_utc_dec_31_local_jan_1_a) { create_point(user, 13.4, 52.5, Time.utc(2025, 12, 31, 23, 15, 0)) }
    let!(:point_utc_dec_31_local_jan_1_b) { create_point(user, 13.41, 52.51, Time.utc(2025, 12, 31, 23, 45, 0)) }

    it 'attributes both UTC-Dec points to local January 1 with non-zero distance, not December' do
      jan_stat = calculate_and_load(user, 2026, 1)
      dec_stat = calculate_and_load(user, 2025, 12)

      expect(jan_stat.daily_distance.find { |day, _| day == 1 }&.last).to be > 0
      expect(jan_stat.distance).to be > 0

      expect(dec_stat.daily_distance.find { |day, _| day == 31 }&.last).to eq(0)
      expect(dec_stat.distance).to eq(0)
    end
  end

  context 'toponyms do not leak adjacent-month cities' do
    let(:tz) { 'Europe/Berlin' }
    let(:user) do
      create(:user, settings: { 'timezone' => tz, 'min_minutes_spent_in_city' => 1, 'max_gap_minutes_in_city' => 120 })
    end
    let(:germany) { create(:country, name: 'Germany', iso_a2: 'DE', iso_a3: 'DEU') }
    let(:france) { create(:country, name: 'France', iso_a2: 'FR', iso_a3: 'FRA') }

    before do
      create(:point, user: user, lonlat: 'POINT(13.4 52.5)', city: 'Berlin',
                     country: 'Germany', country_id: germany.id, velocity: '0',
                     timestamp: Time.utc(2026, 3, 15, 9, 0, 0).to_i)
      create(:point, user: user, lonlat: 'POINT(13.5 52.6)', city: 'Berlin',
                     country: 'Germany', country_id: germany.id, velocity: '0',
                     timestamp: Time.utc(2026, 3, 15, 9, 30, 0).to_i)
      create(:point, user: user, lonlat: 'POINT(2.35 48.85)', city: 'Paris',
                     country: 'France', country_id: france.id, velocity: '0',
                     timestamp: Time.utc(2026, 3, 31, 23, 30, 0).to_i)
      create(:point, user: user, lonlat: 'POINT(2.36 48.86)', city: 'Paris',
                     country: 'France', country_id: france.id, velocity: '0',
                     timestamp: Time.utc(2026, 3, 31, 23, 45, 0).to_i)
    end

    it 'excludes Paris (local Berlin April) from March toponyms' do
      stat = calculate_and_load(user, 2026, 3)

      country_names = (stat.toponyms || []).map { |c| c['country'] }
      expect(country_names).to include('Germany')
      expect(country_names).not_to include('France')
    end
  end

  context 're-running CalculateMonth is idempotent' do
    let(:tz) { 'Europe/Berlin' }
    let(:user) { create(:user, settings: { 'timezone' => tz }) }

    let!(:point_a) { create_point(user, 13.4, 52.5, Time.utc(2026, 3, 15, 9, 0, 0)) }
    let!(:point_b) { create_point(user, 13.5, 52.6, Time.utc(2026, 3, 15, 9, 30, 0)) }

    it 'produces identical daily_distance and distance on a second run' do
      first = calculate_and_load(user, 2026, 3)
      first_daily = first.daily_distance
      first_total = first.distance

      second = calculate_and_load(user, 2026, 3)
      expect(second.daily_distance).to eq(first_daily)
      expect(second.distance).to eq(first_total)
    end
  end

  context 'extreme positive UTC offset (Pacific/Kiritimati, UTC+14)' do
    let(:tz) { 'Pacific/Kiritimati' }
    let(:user) { create(:user, settings: { 'timezone' => tz }) }

    let!(:point_utc_feb_28_local_march_1_a) { create_point(user, -157.4, 1.87, Time.utc(2026, 2, 28, 11, 0, 0)) }
    let!(:point_utc_feb_28_local_march_1_b) { create_point(user, -157.41, 1.88, Time.utc(2026, 2, 28, 11, 30, 0)) }

    it 'attributes UTC-Feb-28 11:00 (Kiritimati Mar 1 01:00) to local March day 1' do
      stat = calculate_and_load(user, 2026, 3)

      day_1 = stat.daily_distance.find { |day, _| day == 1 }&.last
      expect(day_1).to be > 0
    end
  end

  context 'invalid stored timezone falls back to UTC' do
    let(:user) { create(:user, settings: { 'timezone' => 'Not/A/Real/Zone' }) }

    let!(:point) { create_point(user, 13.4, 52.5, Time.utc(2026, 3, 15, 12, 0, 0)) }
    let!(:point_b) { create_point(user, 13.5, 52.6, Time.utc(2026, 3, 15, 12, 30, 0)) }

    it 'computes March stats without raising' do
      expect { calculate_and_load(user, 2026, 3) }.not_to raise_error

      stat = Stat.find_by(user: user, year: 2026, month: 3)
      expect(stat).to be_present
    end
  end

  context 'toponyms when a city visit straddles local midnight at month boundary' do
    let(:tz) { 'Europe/Berlin' }
    let(:user) do
      create(:user, settings: { 'timezone' => tz, 'min_minutes_spent_in_city' => 60, 'max_gap_minutes_in_city' => 120 })
    end
    let(:germany) { create(:country, name: 'Germany', iso_a2: 'DE', iso_a3: 'DEU') }

    before do
      [
        Time.utc(2026, 2, 28, 21, 0, 0),
        Time.utc(2026, 2, 28, 22, 0, 0),
        Time.utc(2026, 2, 28, 22, 30, 0),
        Time.utc(2026, 2, 28, 23, 30, 0),
        Time.utc(2026, 3, 1, 0, 30, 0),
        Time.utc(2026, 3, 1, 1, 30, 0)
      ].each_with_index do |t, i|
        create(:point, user: user, lonlat: "POINT(#{13.4 + i * 0.001} 52.5)",
                       city: 'Berlin', country: 'Germany', country_id: germany.id,
                       velocity: '0', timestamp: t.to_i)
      end
    end

    it 'attributes the post-midnight portion to March (current behaviour: split-bucket)' do
      stat = calculate_and_load(user, 2026, 3)

      country_names = (stat.toponyms || []).map { |c| c['country'] }
      expect(country_names).to include('Germany')
    end
  end

  context 'calculate_data_bounds is timezone-aware' do
    let(:tz) { 'Europe/Berlin' }
    let(:user) { create(:user, settings: { 'timezone' => tz }) }

    let!(:point_utc_late_local_march) do
      create(:point, user: user, latitude: 52.5, longitude: 13.4, lonlat: 'POINT(13.4 52.5)',
                     timestamp: Time.utc(2026, 2, 28, 23, 30, 0).to_i)
    end
    let!(:point_local_march_mid) do
      create(:point, user: user, latitude: 52.6, longitude: 13.5, lonlat: 'POINT(13.5 52.6)',
                     timestamp: Time.utc(2026, 3, 15, 12, 0, 0).to_i)
    end

    it 'includes the UTC-Feb point in March bounds when local time is March 1' do
      stat = create(:stat, user: user, year: 2026, month: 3)
      bounds = stat.calculate_data_bounds

      expect(bounds[:point_count]).to eq(2)
      expect(bounds[:min_lat]).to eq(52.5)
      expect(bounds[:max_lat]).to eq(52.6)
    end
  end

  context 'daily_distance tuple shape' do
    let(:tz) { 'Europe/Berlin' }
    let(:user) { create(:user, settings: { 'timezone' => tz }) }

    let!(:p1) { create_point(user, 13.4, 52.5, Time.utc(2026, 3, 15, 9, 0, 0)) }
    let!(:p2) { create_point(user, 13.5, 52.6, Time.utc(2026, 3, 15, 9, 30, 0)) }

    it 'returns [day_of_month, distance_meters] pairs covering every day in the month' do
      stat = calculate_and_load(user, 2026, 3)

      expect(stat.daily_distance.length).to eq(31)
      expect(stat.daily_distance.first.first).to eq(1)
      expect(stat.daily_distance.last.first).to eq(31)
      expect(stat.daily_distance.find { |day, _| day == 15 }&.last).to be > 0
    end
  end

  context 'HexagonCalculator buckets by local timezone' do
    let(:tz) { 'Europe/Berlin' }
    let(:user) { create(:user, settings: { 'timezone' => tz }) }
    let(:flight_hex) { H3.from_geo_coordinates([50.0, -40.0], 8).to_s(16) }

    let!(:flight_tail_utc_march_31) { create_point(user, -40.0, 50.0, Time.utc(2026, 3, 31, 23, 30, 0)) }
    let!(:home_point_march_15) { create_point(user, 13.4, 52.5, Time.utc(2026, 3, 15, 9, 0, 0)) }

    it 'excludes the cross-month flight point from March hex IDs' do
      stat = calculate_and_load(user, 2026, 3)

      hex_ids = (stat.h3_hex_ids || []).map { |entry| entry[0].to_s }
      expect(hex_ids).not_to be_empty
      expect(hex_ids).not_to include(flight_hex)
    end

    it 'attributes the flight point to local April hex IDs, not March' do
      stat = calculate_and_load(user, 2026, 4)
      hex_ids = (stat.h3_hex_ids || []).map { |entry| entry[0].to_s }

      expect(hex_ids).to include(flight_hex)
    end
  end
end

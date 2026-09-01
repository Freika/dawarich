# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'City presence under sparse tracking' do
  let(:tz) { 'Europe/Berlin' }
  let(:germany) { create(:country, name: 'Germany', iso_a2: 'DE', iso_a3: 'DEU') }

  def stat_for(user, year, month)
    Stats::CalculateMonth.new(user.id, year, month).call
    Stat.find_by(user: user, year: year, month: month)
  end

  def track_day(user, cadence_minutes:, city: 'Berlin', hours: 24)
    day = Time.utc(2026, 3, 10, 0, 0, 0)
    samples = (hours * 60) / cadence_minutes

    (0..samples).each do |i|
      create(:point, user: user, lonlat: 'POINT(13.4 52.5)', city: city,
                     country_name: 'Germany', country_id: germany.id, velocity: '0',
                     timestamp: (day + (i * cadence_minutes).minutes).to_i)
    end
  end

  context 'when a stationary phone reports far less often than it moves' do
    let(:user) { create(:user, settings: { 'timezone' => tz, 'min_minutes_spent_in_city' => 60 }) }

    it 'still credits a full day spent in one city' do
      track_day(user, cadence_minutes: 150)

      cities = (stat_for(user, 2026, 3).toponyms || []).flat_map { |c| c['cities'] }

      expect(cities.map { |c| c['city'] }).to include('Berlin')
      expect(cities.find { |c| c['city'] == 'Berlin' }['stayed_for']).to be >= 60
    end
  end

  context 'when the reporting cadence crosses what used to be the gap threshold' do
    it 'does not fall off a cliff between adjacent cadences' do
      credited = [60, 119, 120, 121, 180].map do |cadence|
        traveller = create(:user, settings: { 'timezone' => tz, 'min_minutes_spent_in_city' => 5 })
        track_day(traveller, cadence_minutes: cadence)

        berlin = (stat_for(traveller, 2026, 3).toponyms || [])
                 .flat_map { |c| c['cities'] }
                 .find { |c| c['city'] == 'Berlin' }

        berlin&.fetch('stayed_for')
      end

      expect(credited).to all(be_present)
      expect(credited).to all(be >= 1200)
    end
  end
end

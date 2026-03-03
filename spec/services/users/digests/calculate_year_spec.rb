# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::Digests::CalculateYear do
  describe '#call' do
    subject(:calculate_digest) { described_class.new(user.id, year).call }

    let(:user) { create(:user) }
    let(:year) { 2024 }

    context 'when user has no stats for the year' do
      it 'returns nil' do
        expect(calculate_digest).to be_nil
      end

      it 'does not create a digest' do
        expect { calculate_digest }.not_to(change { Users::Digest.count })
      end
    end

    context 'when user has stats for the year' do
      let!(:january_stat) do
        create(:stat, user: user, year: 2024, month: 1, distance: 50_000, toponyms: [
                 { 'country' => 'Germany', 'cities' => [
                   { 'city' => 'Berlin', 'stayed_for' => 480 },
                   { 'city' => 'Munich', 'stayed_for' => 240 }
                 ] }
               ])
      end

      let!(:february_stat) do
        create(:stat, user: user, year: 2024, month: 2, distance: 75_000, toponyms: [
                 { 'country' => 'France', 'cities' => [
                   { 'city' => 'Paris', 'stayed_for' => 360 }
                 ] }
               ])
      end

      it 'creates a yearly digest' do
        expect { calculate_digest }.to change { Users::Digest.count }.by(1)
      end

      it 'returns the created digest' do
        expect(calculate_digest).to be_a(Users::Digest)
      end

      it 'sets the correct year' do
        expect(calculate_digest.year).to eq(2024)
      end

      it 'sets the period type to yearly' do
        expect(calculate_digest.period_type).to eq('yearly')
      end

      it 'calculates total distance' do
        expect(calculate_digest.distance).to eq(125_000)
      end

      it 'aggregates countries with their cities' do
        toponyms = calculate_digest.toponyms

        countries = toponyms.map { |t| t['country'] }
        expect(countries).to contain_exactly('France', 'Germany')

        germany = toponyms.find { |t| t['country'] == 'Germany' }
        expect(germany['cities'].map { |c| c['city'] }).to contain_exactly('Berlin', 'Munich')

        france = toponyms.find { |t| t['country'] == 'France' }
        expect(france['cities'].map { |c| c['city'] }).to contain_exactly('Paris')
      end

      it 'builds monthly distances' do
        expect(calculate_digest.monthly_distances['1']).to eq('50000')
        expect(calculate_digest.monthly_distances['2']).to eq('75000')
        expect(calculate_digest.monthly_distances['3']).to eq('0') # Missing month
      end

      it 'calculates time spent by location using hybrid day-based approach' do
        # Create points to test hybrid calculation
        # Jan 1: single country day (Germany) -> full 1440 minutes
        jan_1_10am = Time.zone.local(2024, 1, 1, 10, 0, 0).to_i
        jan_1_11am = Time.zone.local(2024, 1, 1, 11, 0, 0).to_i
        jan_1_12pm = Time.zone.local(2024, 1, 1, 12, 0, 0).to_i
        # Feb 1: single country day (France) -> full 1440 minutes
        feb_1_10am = Time.zone.local(2024, 2, 1, 10, 0, 0).to_i

        create(:point, user: user, timestamp: jan_1_10am, country_name: 'Germany', city: 'Berlin')
        create(:point, user: user, timestamp: jan_1_11am, country_name: 'Germany', city: 'Berlin')
        create(:point, user: user, timestamp: jan_1_12pm, country_name: 'Germany', city: 'Munich')
        create(:point, user: user, timestamp: feb_1_10am, country_name: 'France', city: 'Paris')

        countries = calculate_digest.time_spent_by_location['countries']
        cities = calculate_digest.time_spent_by_location['cities']

        # Germany: 1 full day = 1440 minutes
        germany_country = countries.find { |c| c['name'] == 'Germany' }
        expect(germany_country['minutes']).to eq(1440)

        # France: 1 full day = 1440 minutes
        france_country = countries.find { |c| c['name'] == 'France' }
        expect(france_country['minutes']).to eq(1440)

        # Cities: based on stayed_for from monthly stats (sum across months)
        expect(cities.first['name']).to eq('Berlin')
        expect(cities.first['minutes']).to eq(480)
      end

      it 'calculates all time stats' do
        expect(calculate_digest.all_time_stats['total_distance']).to eq('125000')
      end

      context 'when user visits same country across multiple months' do
        it 'counts each day as a full day for single-country days' do
          # Create hourly points across multiple days in March and July
          mar_start = Time.zone.local(2024, 3, 1, 10, 0, 0).to_i
          jul_start = Time.zone.local(2024, 7, 1, 10, 0, 0).to_i

          # Create 3 days of hourly points in March
          3.times do |day|
            3.times do |hour|
              timestamp = mar_start + (day * 24 * 60 * 60) + (hour * 60 * 60)
              create(:point, user: user, timestamp: timestamp, country_name: 'Germany', city: 'Berlin')
            end
          end

          # Create 3 days of hourly points in July
          3.times do |day|
            3.times do |hour|
              timestamp = jul_start + (day * 24 * 60 * 60) + (hour * 60 * 60)
              create(:point, user: user, timestamp: timestamp, country_name: 'Germany', city: 'Munich')
            end
          end

          # Create the monthly stats
          create(:stat, user: user, year: 2024, month: 3, distance: 10_000, toponyms: [
                   { 'country' => 'Germany', 'cities' => [
                     { 'city' => 'Berlin', 'stayed_for' => 14_400 }
                   ] }
                 ])

          create(:stat, user: user, year: 2024, month: 7, distance: 15_000, toponyms: [
                   { 'country' => 'Germany', 'cities' => [
                     { 'city' => 'Munich', 'stayed_for' => 14_400 }
                   ] }
                 ])

          digest = calculate_digest
          countries = digest.time_spent_by_location['countries']
          germany = countries.find { |c| c['name'] == 'Germany' }

          # Each single-country day = 1440 minutes
          # 6 days total (3 in March + 3 in July) = 6 * 1440 = 8640 minutes
          expect(germany['minutes']).to eq(6 * 1440)

          # Total should equal exactly 6 days
          total_days = germany['minutes'] / 1440.0
          expect(total_days).to eq(6)
        end
      end

      context 'when there are large gaps between points on same day' do
        it 'still counts the full day for single-country day' do
          point_1 = Time.zone.local(2024, 1, 1, 10, 0, 0).to_i
          point_2 = Time.zone.local(2024, 1, 1, 12, 0, 0).to_i  # 2 hours later
          point_3 = Time.zone.local(2024, 1, 1, 18, 0, 0).to_i  # 6 hours later

          create(:point, user: user, timestamp: point_1, country_name: 'Germany')
          create(:point, user: user, timestamp: point_2, country_name: 'Germany')
          create(:point, user: user, timestamp: point_3, country_name: 'Germany')

          digest = calculate_digest
          germany = digest.time_spent_by_location['countries'].find { |c| c['name'] == 'Germany' }

          # Hybrid approach: single-country day = full 1440 minutes
          # regardless of gaps between points
          expect(germany['minutes']).to eq(1440)
        end
      end

      context 'when transitioning between countries on same day' do
        it 'calculates proportional time based on time spans' do
          # Multi-country day: Germany 10:00-10:30, France 11:00-11:30
          point_1 = Time.zone.local(2024, 1, 1, 10, 0, 0).to_i
          point_2 = Time.zone.local(2024, 1, 1, 10, 30, 0).to_i  # In Germany
          point_3 = Time.zone.local(2024, 1, 1, 11, 0, 0).to_i   # Now in France
          point_4 = Time.zone.local(2024, 1, 1, 11, 30, 0).to_i  # Still in France

          create(:point, user: user, timestamp: point_1, country_name: 'Germany')
          create(:point, user: user, timestamp: point_2, country_name: 'Germany')
          create(:point, user: user, timestamp: point_3, country_name: 'France')
          create(:point, user: user, timestamp: point_4, country_name: 'France')

          digest = calculate_digest
          countries = digest.time_spent_by_location['countries']

          germany = countries.find { |c| c['name'] == 'Germany' }
          france = countries.find { |c| c['name'] == 'France' }

          # Germany span: 10:30 - 10:00 = 30 min = 1800 seconds
          # France span: 11:30 - 11:00 = 30 min = 1800 seconds
          # Total spans = 3600 seconds
          # Each country gets 50% of 1440 = 720 minutes
          expect(germany['minutes']).to eq(720)
          expect(france['minutes']).to eq(720)
          # Total = 1440 (exactly one day)
          expect(germany['minutes'] + france['minutes']).to eq(1440)
        end
      end

      context 'when visiting multiple countries on same day' do
        it 'calculates proportional time and never exceeds one day total' do
          # This tests the fix for the original bug: border crossing should not count double
          # France: 8am-9am (1 hour span = 3600 seconds)
          # Germany: 10am-11am (1 hour span = 3600 seconds)
          jan_1_8am = Time.zone.local(2024, 1, 1, 8, 0, 0).to_i
          jan_1_9am = Time.zone.local(2024, 1, 1, 9, 0, 0).to_i
          jan_1_10am = Time.zone.local(2024, 1, 1, 10, 0, 0).to_i # Border crossing
          jan_1_11am = Time.zone.local(2024, 1, 1, 11, 0, 0).to_i

          create(:point, user: user, timestamp: jan_1_8am, country_name: 'France')
          create(:point, user: user, timestamp: jan_1_9am, country_name: 'France')
          create(:point, user: user, timestamp: jan_1_10am, country_name: 'Germany')
          create(:point, user: user, timestamp: jan_1_11am, country_name: 'Germany')

          digest = calculate_digest
          countries = digest.time_spent_by_location['countries']

          france = countries.find { |c| c['name'] == 'France' }
          germany = countries.find { |c| c['name'] == 'Germany' }

          # France span: 3600 seconds, Germany span: 3600 seconds
          # Total spans: 7200 seconds
          # Each gets 50% of 1440 = 720 minutes
          expect(france['minutes']).to eq(720)
          expect(germany['minutes']).to eq(720)
          # Total = 1440 (exactly one day) - NOT 2 days as the bug would have caused
          expect(france['minutes'] + germany['minutes']).to eq(1440)
        end
      end

      context 'when digest already exists' do
        let!(:existing_digest) do
          create(:users_digest, user: user, year: 2024, period_type: :yearly, distance: 10_000)
        end

        it 'updates the existing digest' do
          expect { calculate_digest }.not_to(change { Users::Digest.count })
        end

        it 'updates the distance' do
          calculate_digest
          expect(existing_digest.reload.distance).to eq(125_000)
        end
      end
    end

    context 'with previous year data for comparison' do
      let!(:previous_year_stat) do
        create(:stat, user: user, year: 2023, month: 1, distance: 100_000, toponyms: [
                 { 'country' => 'Germany', 'cities' => [{ 'city' => 'Berlin' }] }
               ])
      end

      let!(:current_year_stat) do
        create(:stat, user: user, year: 2024, month: 1, distance: 150_000, toponyms: [
                 { 'country' => 'Germany', 'cities' => [{ 'city' => 'Berlin' }] },
                 { 'country' => 'France', 'cities' => [{ 'city' => 'Paris' }] }
               ])
      end

      it 'calculates year over year comparison' do
        expect(calculate_digest.year_over_year['previous_year']).to eq(2023)
        expect(calculate_digest.year_over_year['distance_change_percent']).to eq(50)
      end

      it 'identifies first time visits' do
        expect(calculate_digest.first_time_visits['countries']).to eq(['France'])
        expect(calculate_digest.first_time_visits['cities']).to eq(['Paris'])
      end
    end

    context 'when user not found' do
      it 'raises ActiveRecord::RecordNotFound' do
        expect do
          described_class.new(999_999, year).call
        end.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end
end

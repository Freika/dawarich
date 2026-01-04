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

      it 'calculates time spent by location using actual minutes between consecutive points' do
        # Create points with specific gaps to test actual minute calculation
        jan_1_10am = Time.zone.local(2024, 1, 1, 10, 0, 0).to_i
        jan_1_11am = Time.zone.local(2024, 1, 1, 11, 0, 0).to_i  # 60 min later
        jan_1_12pm = Time.zone.local(2024, 1, 1, 12, 0, 0).to_i  # 60 min later
        feb_1_10am = Time.zone.local(2024, 2, 1, 10, 0, 0).to_i

        create(:point, user: user, timestamp: jan_1_10am, country_name: 'Germany', city: 'Berlin')
        create(:point, user: user, timestamp: jan_1_11am, country_name: 'Germany', city: 'Berlin')
        create(:point, user: user, timestamp: jan_1_12pm, country_name: 'Germany', city: 'Munich')
        create(:point, user: user, timestamp: feb_1_10am, country_name: 'France', city: 'Paris')

        countries = calculate_digest.time_spent_by_location['countries']
        cities = calculate_digest.time_spent_by_location['cities']

        # Germany: 60 min (10am->11am) + 60 min (11am->12pm) = 120 minutes
        germany_country = countries.find { |c| c['name'] == 'Germany' }
        expect(germany_country['minutes']).to eq(120)

        # France: only 1 point, so 0 minutes (no consecutive pair)
        france_country = countries.find { |c| c['name'] == 'France' }
        expect(france_country).to be_nil # No time counted for single point

        # Cities: based on stayed_for from monthly stats (sum across months)
        expect(cities.first['name']).to eq('Berlin')
        expect(cities.first['minutes']).to eq(480)
      end

      it 'calculates all time stats' do
        expect(calculate_digest.all_time_stats['total_distance']).to eq('125000')
      end

      context 'when user visits same country across multiple months' do
        it 'calculates actual minutes from consecutive point pairs' do
          # Create hourly points across multiple days in March and July
          mar_start = Time.zone.local(2024, 3, 1, 10, 0, 0).to_i
          jul_start = Time.zone.local(2024, 7, 1, 10, 0, 0).to_i

          # Create 3 days of hourly points in March (3 points per day = 2 gaps of 60 min each)
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

          # Create the monthly stats (simulating what would be created by the stats calculation)
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

          # Each day: 2 gaps of 60 minutes = 120 minutes
          # 6 days total (3 in March + 3 in July) = 720 minutes
          # But gaps between days are > 60 min threshold, so not counted
          expect(germany['minutes']).to eq(6 * 2 * 60)

          # Total should be much less than 365 days
          total_hours = germany['minutes'] / 60.0
          expect(total_hours).to eq(12) # 12 hours of tracked time
        end
      end

      context 'when there are large gaps between points' do
        it 'does not count time during gaps exceeding 60 minute threshold' do
          point_1 = Time.zone.local(2024, 1, 1, 10, 0, 0).to_i
          point_2 = Time.zone.local(2024, 1, 1, 12, 0, 0).to_i  # 2 hours later (> 1 hour threshold)
          point_3 = Time.zone.local(2024, 1, 1, 13, 0, 0).to_i  # 1 hour after point_2

          create(:point, user: user, timestamp: point_1, country_name: 'Germany')
          create(:point, user: user, timestamp: point_2, country_name: 'Germany')
          create(:point, user: user, timestamp: point_3, country_name: 'Germany')

          digest = calculate_digest
          germany = digest.time_spent_by_location['countries'].find { |c| c['name'] == 'Germany' }

          # Only point_2 -> point_3 gap (60 min) should be counted
          # point_1 -> point_2 gap (120 min) exceeds threshold
          expect(germany['minutes']).to eq(60)
        end
      end

      context 'when transitioning between countries' do
        it 'does not count transition time' do
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

          expect(germany['minutes']).to eq(30)  # point_1 -> point_2
          expect(france['minutes']).to eq(30)   # point_3 -> point_4
          # Transition time (point_2 -> point_3) is NOT counted
        end
      end

      context 'when visiting multiple countries on same day' do
        it 'does not exceed the actual time in the day' do
          # This tests the fix for the original bug: border crossing should not count double
          jan_1_8am = Time.zone.local(2024, 1, 1, 8, 0, 0).to_i
          jan_1_9am = Time.zone.local(2024, 1, 1, 9, 0, 0).to_i
          jan_1_10am = Time.zone.local(2024, 1, 1, 10, 0, 0).to_i  # Border crossing
          jan_1_11am = Time.zone.local(2024, 1, 1, 11, 0, 0).to_i

          create(:point, user: user, timestamp: jan_1_8am, country_name: 'France')
          create(:point, user: user, timestamp: jan_1_9am, country_name: 'France')
          create(:point, user: user, timestamp: jan_1_10am, country_name: 'Germany')
          create(:point, user: user, timestamp: jan_1_11am, country_name: 'Germany')

          digest = calculate_digest
          countries = digest.time_spent_by_location['countries']

          france = countries.find { |c| c['name'] == 'France' }
          germany = countries.find { |c| c['name'] == 'Germany' }

          # France: 60 min (8am->9am)
          # Germany: 60 min (10am->11am)
          # Total: 120 min (2 hours) - NOT 2 days (2880 min) as the bug would have caused
          expect(france['minutes']).to eq(60)
          expect(germany['minutes']).to eq(60)
          expect(france['minutes'] + germany['minutes']).to eq(120)
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

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

      it 'calculates time spent by location' do
        # Create points to enable country time calculation based on unique days
        jan_1 = Time.zone.local(2024, 1, 1, 10, 0, 0).to_i
        jan_2 = Time.zone.local(2024, 1, 2, 10, 0, 0).to_i
        feb_1 = Time.zone.local(2024, 2, 1, 10, 0, 0).to_i

        create(:point, user: user, timestamp: jan_1, country_name: 'Germany', city: 'Berlin')
        create(:point, user: user, timestamp: jan_2, country_name: 'Germany', city: 'Munich')
        create(:point, user: user, timestamp: feb_1, country_name: 'France', city: 'Paris')

        countries = calculate_digest.time_spent_by_location['countries']
        cities = calculate_digest.time_spent_by_location['cities']

        # Countries: based on unique days (2 days in Germany, 1 day in France)
        germany_country = countries.find { |c| c['name'] == 'Germany' }
        expect(germany_country['minutes']).to eq(2 * 24 * 60) # 2 days = 2880 minutes

        # Cities: based on stayed_for from monthly stats (sum across months)
        expect(cities.first['name']).to eq('Berlin')
        expect(cities.first['minutes']).to eq(480)
      end

      it 'calculates all time stats' do
        expect(calculate_digest.all_time_stats['total_distance']).to eq('125000')
      end

      context 'when user visits same country across multiple months' do
        it 'does not double-count days' do
          # Create a user who was in Germany for 10 days in March and 10 days in July
          # If we summed the stayed_for values from cities, we might get inflated numbers
          # The fix counts unique days to prevent exceeding 365 days per year
          mar_start = Time.zone.local(2024, 3, 1, 10, 0, 0).to_i
          jul_start = Time.zone.local(2024, 7, 1, 10, 0, 0).to_i

          # Create 10 days of points in March
          10.times do |i|
            timestamp = mar_start + (i * 24 * 60 * 60)
            create(:point, user: user, timestamp: timestamp, country_name: 'Germany', city: 'Berlin')
          end

          # Create 10 days of points in July
          10.times do |i|
            timestamp = jul_start + (i * 24 * 60 * 60)
            create(:point, user: user, timestamp: timestamp, country_name: 'Germany', city: 'Munich')
          end

          # Create the monthly stats (simulating what would be created by the stats calculation)
          create(:stat, user: user, year: 2024, month: 3, distance: 10_000, toponyms: [
            { 'country' => 'Germany', 'cities' => [
              { 'city' => 'Berlin', 'stayed_for' => 14_400 } # 10 days in minutes
            ] }
          ])

          create(:stat, user: user, year: 2024, month: 7, distance: 15_000, toponyms: [
            { 'country' => 'Germany', 'cities' => [
              { 'city' => 'Munich', 'stayed_for' => 14_400 } # 10 days in minutes
            ] }
          ])

          digest = calculate_digest
          countries = digest.time_spent_by_location['countries']
          germany = countries.find { |c| c['name'] == 'Germany' }

          # Should be 20 days total (10 unique days in Mar + 10 unique days in Jul)
          expected_minutes = 20 * 24 * 60 # 28,800 minutes
          expect(germany['minutes']).to eq(expected_minutes)

          # Verify this is less than 365 days (the bug would cause inflated numbers)
          total_days = germany['minutes'] / (24 * 60)
          expect(total_days).to be <= 365
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

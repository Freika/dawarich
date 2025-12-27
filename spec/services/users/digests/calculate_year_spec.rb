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

      it 'aggregates countries' do
        expect(calculate_digest.toponyms['countries']).to contain_exactly('France', 'Germany')
      end

      it 'aggregates cities' do
        expect(calculate_digest.toponyms['cities']).to contain_exactly('Berlin', 'Munich', 'Paris')
      end

      it 'builds monthly distances' do
        expect(calculate_digest.monthly_distances['1']).to eq(50_000)
        expect(calculate_digest.monthly_distances['2']).to eq(75_000)
        expect(calculate_digest.monthly_distances['3']).to eq(0) # Missing month
      end

      it 'calculates time spent by location' do
        countries = calculate_digest.time_spent_by_location['countries']
        cities = calculate_digest.time_spent_by_location['cities']

        expect(countries.first['name']).to eq('Germany')
        expect(countries.first['minutes']).to eq(720) # 480 + 240
        expect(cities.first['name']).to eq('Berlin')
      end

      it 'calculates all time stats' do
        expect(calculate_digest.all_time_stats['total_distance']).to eq(125_000)
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

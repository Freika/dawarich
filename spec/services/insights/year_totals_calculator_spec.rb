# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Insights::YearTotalsCalculator do
  describe '#call' do
    subject(:calculator) { described_class.new(stats, distance_unit: distance_unit) }

    let(:user) { create(:user) }
    let(:distance_unit) { 'km' }

    context 'when there are no stats' do
      let(:stats) { Stat.none }

      it 'returns zero for all numeric values' do
        result = calculator.call

        expect(result.total_distance).to eq(0)
        expect(result.countries_count).to eq(0)
        expect(result.cities_count).to eq(0)
        expect(result.days_traveling).to eq(0)
      end

      it 'returns empty collections' do
        result = calculator.call

        expect(result.countries_list).to eq([])
        expect(result.biggest_month).to be_nil
      end
    end

    context 'when there are stats with data' do
      let!(:stat1) do
        create(:stat,
               user: user,
               year: 2024,
               month: 1,
               distance: 100_000, # 100 km
               daily_distance: { '1' => 50_000, '2' => 50_000 },
               toponyms: [
                 {
                   'country' => 'Germany',
                   'cities' => [
                     { 'city' => 'Berlin', 'stayed_for' => 120 },
                     { 'city' => 'Munich', 'stayed_for' => 60 }
                   ]
                 }
               ])
      end

      let!(:stat2) do
        create(:stat,
               user: user,
               year: 2024,
               month: 2,
               distance: 200_000, # 200 km
               daily_distance: { '1' => 100_000, '2' => 50_000, '3' => 50_000 },
               toponyms: [
                 {
                   'country' => 'France',
                   'cities' => [
                     { 'city' => 'Paris', 'stayed_for' => 180 }
                   ]
                 },
                 {
                   'country' => 'Germany',
                   'cities' => [
                     { 'city' => 'Berlin', 'stayed_for' => 60 }
                   ]
                 }
               ])
      end

      let(:stats) { user.stats.where(year: 2024).order(:month) }

      it 'calculates total distance correctly in km' do
        result = calculator.call

        expect(result.total_distance).to eq(300) # 300 km
      end

      context 'when distance unit is miles' do
        let(:distance_unit) { 'mi' }

        it 'converts distance to miles' do
          result = calculator.call

          # 300 km ≈ 186 miles
          expect(result.total_distance).to be_within(5).of(186)
        end
      end

      it 'counts unique countries' do
        result = calculator.call

        expect(result.countries_count).to eq(2)
        expect(result.countries_list).to contain_exactly('France', 'Germany')
      end

      it 'counts unique cities' do
        result = calculator.call

        # Berlin appears twice but should only count once
        expect(result.cities_count).to eq(3) # Berlin, Munich, Paris
      end

      it 'calculates days traveling' do
        result = calculator.call

        # stat1 has 2 days, stat2 has 3 days
        expect(result.days_traveling).to eq(5)
      end

      it 'finds the biggest month' do
        result = calculator.call

        expect(result.biggest_month[:month]).to eq('February')
        expect(result.biggest_month[:distance]).to eq(200) # 200 km
      end
    end

    context 'when stats have empty or nil toponyms' do
      let!(:stat) do
        create(:stat,
               user: user,
               year: 2024,
               month: 1,
               distance: 50_000,
               daily_distance: {},
               toponyms: nil)
      end

      let(:stats) { user.stats.where(year: 2024) }

      it 'handles nil toponyms gracefully' do
        result = calculator.call

        expect(result.countries_count).to eq(0)
        expect(result.cities_count).to eq(0)
      end
    end

    context 'when stats have malformed toponyms' do
      let!(:stat) do
        create(:stat,
               user: user,
               year: 2024,
               month: 1,
               distance: 50_000,
               daily_distance: { '1' => 0 },
               toponyms: [
                 { 'country' => 'Spain', 'cities' => 'not_an_array' },
                 { 'country' => nil, 'cities' => [] },
                 'not_a_hash',
                 { 'country' => 'Italy', 'cities' => [{ 'city' => nil }, { 'not_city' => 'Rome' }] }
               ])
      end

      let(:stats) { user.stats.where(year: 2024) }

      it 'handles malformed data gracefully' do
        result = calculator.call

        expect(result.countries_count).to eq(2) # Spain and Italy
        expect(result.cities_count).to eq(0) # No valid cities
      end
    end

    context 'when calculating days traveling' do
      let!(:stat) do
        create(:stat,
               user: user,
               year: 2024,
               month: 1,
               distance: 100_000,
               daily_distance: {
                 '1' => 1000,
                 '2' => 0,
                 '3' => 500,
                 '4' => nil,
                 '5' => '100'
               },
               toponyms: [])
      end

      let(:stats) { user.stats.where(year: 2024) }

      it 'only counts days with positive distance' do
        result = calculator.call

        # Day 1: 1000 (counted), Day 2: 0 (not counted), Day 3: 500 (counted)
        # Day 4: nil (not counted), Day 5: "100" (counted as integer)
        expect(result.days_traveling).to eq(3)
      end
    end

    context 'when all stats have zero distance' do
      let!(:stat) do
        create(:stat,
               user: user,
               year: 2024,
               month: 1,
               distance: 0,
               daily_distance: {},
               toponyms: [])
      end

      let(:stats) { user.stats.where(year: 2024) }

      it 'returns nil for biggest month' do
        result = calculator.call

        expect(result.biggest_month).to be_nil
      end
    end
  end
end

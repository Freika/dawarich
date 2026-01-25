# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Insights::YearComparisonCalculator do
  describe '#call' do
    subject(:calculator) do
      described_class.new(current_totals, previous_year_stats, distance_unit: distance_unit)
    end

    let(:user) { create(:user) }
    let(:distance_unit) { 'km' }

    let(:current_totals) do
      Insights::YearTotalsCalculator::Result.new(
        total_distance: 500,
        countries_count: 5,
        cities_count: 15,
        countries_list: %w[Germany France Spain Italy Portugal],
        days_traveling: 50,
        biggest_month: { month: 'July', distance: 150 }
      )
    end

    context 'when there are previous year stats' do
      let!(:prev_stat1) do
        create(:stat,
               user: user,
               year: 2023,
               month: 1,
               distance: 150_000, # 150 km
               daily_distance: { '1' => 50_000, '2' => 50_000, '3' => 50_000 },
               toponyms: [
                 {
                   'country' => 'Germany',
                   'cities' => [
                     { 'city' => 'Berlin', 'stayed_for' => 120 }
                   ]
                 }
               ])
      end

      let!(:prev_stat2) do
        create(:stat,
               user: user,
               year: 2023,
               month: 2,
               distance: 100_000, # 100 km
               daily_distance: { '1' => 50_000, '2' => 50_000 },
               toponyms: [
                 {
                   'country' => 'France',
                   'cities' => [
                     { 'city' => 'Paris', 'stayed_for' => 180 }
                   ]
                 }
               ])
      end

      let(:previous_year_stats) { user.stats.where(year: 2023).order(:month) }

      it 'calculates previous year totals' do
        result = calculator.call

        expect(result.prev_total_distance).to eq(250) # 250 km
        expect(result.prev_countries_count).to eq(2)
        expect(result.prev_cities_count).to eq(2)
        expect(result.prev_days_traveling).to eq(5)
      end

      it 'finds previous year biggest month' do
        result = calculator.call

        expect(result.prev_biggest_month[:month]).to eq('January')
        expect(result.prev_biggest_month[:distance]).to eq(150)
      end

      it 'calculates distance change as percentage' do
        result = calculator.call

        # Current: 500, Previous: 250
        # Change: ((500 - 250) / 250) * 100 = 100%
        expect(result.distance_change).to eq(100)
      end

      it 'calculates countries change as absolute difference' do
        result = calculator.call

        # Current: 5, Previous: 2
        # Change: 5 - 2 = 3
        expect(result.countries_change).to eq(3)
      end

      it 'calculates cities change as percentage' do
        result = calculator.call

        # Current: 15, Previous: 2
        # Change: ((15 - 2) / 2) * 100 = 650%
        expect(result.cities_change).to eq(650)
      end

      it 'calculates days change as percentage' do
        result = calculator.call

        # Current: 50, Previous: 5
        # Change: ((50 - 5) / 5) * 100 = 900%
        expect(result.days_change).to eq(900)
      end
    end

    context 'when previous year has no stats' do
      let(:previous_year_stats) { Stat.none }

      it 'returns zero for previous year values' do
        result = calculator.call

        expect(result.prev_total_distance).to eq(0)
        expect(result.prev_countries_count).to eq(0)
        expect(result.prev_cities_count).to eq(0)
        expect(result.prev_days_traveling).to eq(0)
        expect(result.prev_biggest_month).to be_nil
      end

      it 'returns zero for percentage changes when previous is zero' do
        result = calculator.call

        expect(result.distance_change).to eq(0)
        expect(result.cities_change).to eq(0)
        expect(result.days_change).to eq(0)
      end

      it 'calculates absolute countries change' do
        result = calculator.call

        expect(result.countries_change).to eq(5)
      end
    end

    context 'when current year has lower values' do
      let(:current_totals) do
        Insights::YearTotalsCalculator::Result.new(
          total_distance: 100,
          countries_count: 1,
          cities_count: 2,
          countries_list: ['Germany'],
          days_traveling: 10,
          biggest_month: { month: 'March', distance: 50 }
        )
      end

      let!(:prev_stat) do
        create(:stat,
               user: user,
               year: 2023,
               month: 1,
               distance: 200_000, # 200 km
               daily_distance: { '1' => 100_000, '2' => 100_000 },
               toponyms: [
                 {
                   'country' => 'Germany',
                   'cities' => [
                     { 'city' => 'Berlin', 'stayed_for' => 120 },
                     { 'city' => 'Munich', 'stayed_for' => 60 }
                   ]
                 },
                 {
                   'country' => 'France',
                   'cities' => [
                     { 'city' => 'Paris', 'stayed_for' => 180 }
                   ]
                 }
               ])
      end

      let(:previous_year_stats) { user.stats.where(year: 2023) }

      it 'calculates negative percentage change' do
        result = calculator.call

        # Current: 100, Previous: 200
        # Change: ((100 - 200) / 200) * 100 = -50%
        expect(result.distance_change).to eq(-50)
      end

      it 'calculates negative countries change' do
        result = calculator.call

        # Current: 1, Previous: 2
        expect(result.countries_change).to eq(-1)
      end
    end

    context 'with miles distance unit' do
      let(:distance_unit) { 'mi' }

      let!(:prev_stat) do
        create(:stat,
               user: user,
               year: 2023,
               month: 1,
               distance: 160_934, # ~100 miles in meters
               daily_distance: { '1' => 80_467, '2' => 80_467 },
               toponyms: [])
      end

      let(:previous_year_stats) { user.stats.where(year: 2023) }

      it 'converts previous distance to miles' do
        result = calculator.call

        expect(result.prev_total_distance).to be_within(5).of(100)
      end
    end
  end
end

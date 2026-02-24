# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::Digests::YearOverYearCalculator do
  describe '#call' do
    subject(:calculator) { described_class.new(user, year).call }

    let(:user) { create(:user) }
    let(:year) { 2024 }

    context 'when user has no previous year data' do
      let!(:current_year_stats) do
        create(:stat, user: user, year: 2024, month: 1, distance: 100_000)
      end

      it 'returns empty hash' do
        expect(calculator).to eq({})
      end
    end

    context 'when user has previous year data' do
      let!(:previous_year_stats) do
        [
          create(:stat, user: user, year: 2023, month: 1, distance: 50_000, toponyms: [
                   { 'country' => 'Germany', 'cities' => [{ 'city' => 'Berlin' }] }
                 ]),
          create(:stat, user: user, year: 2023, month: 2, distance: 50_000, toponyms: [
                   { 'country' => 'France', 'cities' => [{ 'city' => 'Paris' }] }
                 ])
        ]
      end

      let!(:current_year_stats) do
        [
          create(:stat, user: user, year: 2024, month: 1, distance: 75_000, toponyms: [
                   { 'country' => 'Germany', 'cities' => [{ 'city' => 'Berlin' }, { 'city' => 'Munich' }] }
                 ]),
          create(:stat, user: user, year: 2024, month: 2, distance: 75_000, toponyms: [
                   { 'country' => 'Spain', 'cities' => [{ 'city' => 'Madrid' }] }
                 ])
        ]
      end

      it 'returns previous year' do
        expect(calculator['previous_year']).to eq(2023)
      end

      it 'calculates distance change percent' do
        # Previous: 100,000m, Current: 150,000m = 50% increase
        expect(calculator['distance_change_percent']).to eq(50)
      end

      it 'calculates countries change' do
        # Previous: 2 (Germany, France), Current: 2 (Germany, Spain)
        expect(calculator['countries_change']).to eq(0)
      end

      it 'calculates cities change' do
        # Previous: 2 (Berlin, Paris), Current: 3 (Berlin, Munich, Madrid)
        expect(calculator['cities_change']).to eq(1)
      end
    end

    context 'when distance decreased' do
      let!(:previous_year_stats) do
        create(:stat, user: user, year: 2023, month: 1, distance: 200_000)
      end

      let!(:current_year_stats) do
        create(:stat, user: user, year: 2024, month: 1, distance: 100_000)
      end

      it 'returns negative distance change percent' do
        expect(calculator['distance_change_percent']).to eq(-50)
      end
    end

    context 'when previous year distance is zero' do
      let!(:previous_year_stats) do
        create(:stat, user: user, year: 2023, month: 1, distance: 0)
      end

      let!(:current_year_stats) do
        create(:stat, user: user, year: 2024, month: 1, distance: 100_000)
      end

      it 'returns nil for distance change percent' do
        expect(calculator['distance_change_percent']).to be_nil
      end
    end

    context 'when countries and cities decreased' do
      let!(:previous_year_stats) do
        create(:stat, user: user, year: 2023, month: 1, distance: 100_000, toponyms: [
                 { 'country' => 'Germany', 'cities' => [{ 'city' => 'Berlin' }, { 'city' => 'Munich' }] },
                 { 'country' => 'France', 'cities' => [{ 'city' => 'Paris' }] }
               ])
      end

      let!(:current_year_stats) do
        create(:stat, user: user, year: 2024, month: 1, distance: 100_000, toponyms: [
                 { 'country' => 'Germany', 'cities' => [{ 'city' => 'Berlin' }] }
               ])
      end

      it 'returns negative countries change' do
        expect(calculator['countries_change']).to eq(-1)
      end

      it 'returns negative cities change' do
        expect(calculator['cities_change']).to eq(-2)
      end
    end
  end
end

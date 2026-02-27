# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::Digests::FirstTimeVisitsCalculator do
  describe '#call' do
    subject(:calculator) { described_class.new(user, year).call }

    let(:user) { create(:user) }
    let(:year) { 2024 }

    context 'when user has no previous years' do
      let!(:current_year_stats) do
        [
          create(:stat, user: user, year: 2024, month: 1, toponyms: [
                   { 'country' => 'Germany', 'cities' => [{ 'city' => 'Berlin' }] }
                 ]),
          create(:stat, user: user, year: 2024, month: 2, toponyms: [
                   { 'country' => 'France', 'cities' => [{ 'city' => 'Paris' }] }
                 ])
        ]
      end

      it 'returns all countries as first time' do
        expect(calculator['countries']).to contain_exactly('France', 'Germany')
      end

      it 'returns all cities as first time' do
        expect(calculator['cities']).to contain_exactly('Berlin', 'Paris')
      end
    end

    context 'when user has previous years data' do
      let!(:previous_year_stats) do
        create(:stat, user: user, year: 2023, month: 1, toponyms: [
                 { 'country' => 'Germany', 'cities' => [{ 'city' => 'Berlin' }] }
               ])
      end

      let!(:current_year_stats) do
        [
          create(:stat, user: user, year: 2024, month: 1, toponyms: [
                   { 'country' => 'Germany', 'cities' => [{ 'city' => 'Berlin' }, { 'city' => 'Munich' }] }
                 ]),
          create(:stat, user: user, year: 2024, month: 2, toponyms: [
                   { 'country' => 'France', 'cities' => [{ 'city' => 'Paris' }] }
                 ])
        ]
      end

      it 'returns only new countries as first time' do
        expect(calculator['countries']).to eq(['France'])
      end

      it 'returns only new cities as first time' do
        expect(calculator['cities']).to contain_exactly('Munich', 'Paris')
      end
    end

    context 'when user has multiple previous years' do
      let!(:stats_2022) do
        create(:stat, user: user, year: 2022, month: 1, toponyms: [
                 { 'country' => 'Germany', 'cities' => [{ 'city' => 'Berlin' }] }
               ])
      end

      let!(:stats_2023) do
        create(:stat, user: user, year: 2023, month: 1, toponyms: [
                 { 'country' => 'France', 'cities' => [{ 'city' => 'Paris' }] }
               ])
      end

      let!(:current_year_stats) do
        create(:stat, user: user, year: 2024, month: 1, toponyms: [
                 { 'country' => 'Spain', 'cities' => [{ 'city' => 'Madrid' }] },
                 { 'country' => 'Germany', 'cities' => [{ 'city' => 'Berlin' }] }
               ])
      end

      it 'considers all previous years when determining first time visits' do
        expect(calculator['countries']).to eq(['Spain'])
        expect(calculator['cities']).to eq(['Madrid'])
      end
    end

    context 'when user has no stats for current year' do
      it 'returns empty arrays' do
        expect(calculator['countries']).to eq([])
        expect(calculator['cities']).to eq([])
      end
    end

    context 'when toponyms have invalid format' do
      let!(:current_year_stats) do
        create(:stat, user: user, year: 2024, month: 1, toponyms: nil)
      end

      it 'handles nil toponyms gracefully' do
        expect(calculator['countries']).to eq([])
        expect(calculator['cities']).to eq([])
      end
    end
  end
end

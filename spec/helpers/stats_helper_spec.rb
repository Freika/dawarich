# frozen_string_literal: true

require 'rails_helper'

RSpec.describe StatsHelper, type: :helper do
  describe '#normalize_country_name' do
    let!(:country) do
      Country.find_or_create_by!(name: 'Tanzania') do |c|
        c.iso_a2 = 'TZ'
        c.iso_a3 = 'TZA'
        c.geom = 'MULTIPOLYGON (((0 0, 1 0, 1 1, 0 1, 0 0)))'
      end
    end

    it 'returns canonical name for a known country variant' do
      expect(helper.send(:normalize_country_name, 'Tanzania')).to eq('Tanzania')
    end

    it 'returns the original name when not found in Country table' do
      expect(helper.send(:normalize_country_name, 'Unknown Land')).to eq('Unknown Land')
    end

    it 'returns nil for blank input' do
      expect(helper.send(:normalize_country_name, nil)).to be_nil
      expect(helper.send(:normalize_country_name, '')).to be_nil
    end
  end

  describe '#collect_countries_and_cities (private)' do
    let!(:tanzania) do
      Country.find_or_create_by!(name: 'Tanzania') do |c|
        c.iso_a2 = 'TZ'
        c.iso_a3 = 'TZA'
        c.geom = 'MULTIPOLYGON (((0 0, 1 0, 1 1, 0 1, 0 0)))'
      end
    end

    let(:user) { create(:user) }

    let(:stats) do
      [
        create(:stat, user: user, year: 2025, month: 1, toponyms: [
                 { 'country' => 'Tanzania', 'cities' => [{ 'city' => 'Dar es Salaam' }] }
               ]),
        create(:stat, user: user, year: 2025, month: 2, toponyms: [
                 { 'country' => 'Tanzania', 'cities' => [{ 'city' => 'Arusha' }] }
               ])
      ]
    end

    it 'deduplicates countries with canonical names' do
      countries, cities = helper.send(:collect_countries_and_cities, stats)

      expect(countries).to eq(['Tanzania'])
      expect(cities).to contain_exactly('Dar es Salaam', 'Arusha')
    end
  end
end

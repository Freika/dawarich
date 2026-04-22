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

    # Regression for https://github.com/Freika/dawarich/issues/2434
    # Multiple Country rows may share the same iso_a2 (e.g., overseas territories,
    # disputed regions). The old implementation inverted names_to_iso_a2, so the
    # last-seen name for a given code clobbered the canonical one, turning
    # "France" into "Scarborough Reef" on the stats page.
    it 'resolves to the ISO 3166 canonical name even when DB has duplicate iso_a2 rows' do
      Country.find_or_create_by!(name: 'France') do |c|
        c.iso_a2 = 'FR'
        c.iso_a3 = 'FRA'
        c.geom = 'MULTIPOLYGON (((0 0, 1 0, 1 1, 0 1, 0 0)))'
      end
      Country.find_or_create_by!(name: 'Scarborough Reef') do |c|
        c.iso_a2 = 'FR'
        c.iso_a3 = 'FRA'
        c.geom = 'MULTIPOLYGON (((2 2, 3 2, 3 3, 2 3, 2 2)))'
      end

      expect(helper.send(:normalize_country_name, 'France')).to eq('France')
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

  describe '#countries_visited' do
    let(:user) { create(:user) }

    it 'excludes flyover countries with empty cities' do
      stat = create(:stat, user:, year: 2025, month: 1, toponyms: [
                      { 'country' => 'France', 'cities' => [{ 'city' => 'Paris', 'points' => 5 }] },
                      { 'country' => 'Germany', 'cities' => [] },
                      { 'country' => nil, 'cities' => [] }
                    ])

      expect(helper.countries_visited(stat)).to eq(1)
    end
  end

  describe '#countries_and_cities_stat_for_month' do
    let(:user) { create(:user) }

    it 'excludes flyover countries from count' do
      stat = create(:stat, user:, year: 2025, month: 1, toponyms: [
                      { 'country' => 'France', 'cities' => [{ 'city' => 'Paris', 'points' => 5 }] },
                      { 'country' => 'Germany', 'cities' => [] }
                    ])

      expect(helper.countries_and_cities_stat_for_month(stat)).to eq('1 countries, 1 cities')
    end
  end
end

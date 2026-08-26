# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Countries::NameAliases do
  describe '.canonical' do
    it 'maps a geocoder name onto its seeded counterpart' do
      expect(described_class.canonical('United States')).to eq('United States of America')
    end

    it 'passes an already-canonical name through untouched' do
      expect(described_class.canonical('Germany')).to eq('Germany')
    end
  end

  # A Natural Earth data refresh that renames a country would silently break
  # its aliases: the backfill would match nothing and rows would quietly stay
  # unresolved. Pin every canonical value to the shipped seed file.
  describe 'seed consistency' do
    it 'maps every alias onto a name that exists verbatim in the seed data' do
      seeded = Oj.load(File.read(Rails.root.join('lib/assets/countries.geojson')))['features']
                 .map { |feature| feature['properties']['name'] }

      missing = described_class::ALIASES.values.uniq - seeded
      expect(missing).to be_empty
    end

    it 'never aliases a name the seed already carries' do
      seeded = Oj.load(File.read(Rails.root.join('lib/assets/countries.geojson')))['features']
                 .map { |feature| feature['properties']['name'] }

      shadowed = described_class::ALIASES.keys & seeded
      expect(shadowed).to be_empty
    end
  end

  describe '.values_sql' do
    it 'renders every pair as a quoted VALUES row' do
      sql = described_class.values_sql

      expect(sql).to start_with('(VALUES ')
      expect(sql).to include("('United States', 'United States of America')")
      expect(sql.scan("('").size).to eq(described_class::ALIASES.size)
    end
  end
end

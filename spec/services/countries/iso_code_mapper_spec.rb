# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Countries::IsoCodeMapper do
  describe '.iso_a3_from_a2' do
    it 'returns correct ISO A3 code for valid ISO A2 code' do
      expect(described_class.iso_a3_from_a2('DE')).to eq('DEU')
      expect(described_class.iso_a3_from_a2('US')).to eq('USA')
      expect(described_class.iso_a3_from_a2('GB')).to eq('GBR')
    end

    it 'handles lowercase input' do
      expect(described_class.iso_a3_from_a2('de')).to eq('DEU')
    end

    it 'returns nil for invalid ISO A2 code' do
      expect(described_class.iso_a3_from_a2('XX')).to be_nil
      expect(described_class.iso_a3_from_a2('')).to be_nil
      expect(described_class.iso_a3_from_a2(nil)).to be_nil
    end
  end

  describe '.iso_codes_from_country_name' do
    it 'returns correct ISO codes for exact country name match' do
      iso_a2, iso_a3 = described_class.iso_codes_from_country_name('Germany')
      expect(iso_a2).to eq('DE')
      expect(iso_a3).to eq('DEU')
    end

    it 'returns correct ISO codes for country name aliases' do
      iso_a2, iso_a3 = described_class.iso_codes_from_country_name('Russia')
      expect(iso_a2).to eq('RU')
      expect(iso_a3).to eq('RUS')

      iso_a2, iso_a3 = described_class.iso_codes_from_country_name('USA')
      expect(iso_a2).to eq('US')
      expect(iso_a3).to eq('USA')
    end

    it 'handles case-insensitive matching' do
      iso_a2, iso_a3 = described_class.iso_codes_from_country_name('GERMANY')
      expect(iso_a2).to eq('DE')
      expect(iso_a3).to eq('DEU')

      iso_a2, iso_a3 = described_class.iso_codes_from_country_name('germany')
      expect(iso_a2).to eq('DE')
      expect(iso_a3).to eq('DEU')
    end

    it 'handles partial matching' do
      # This should find "United States" when searching for "United States of America"
      iso_a2, iso_a3 = described_class.iso_codes_from_country_name('United States of America')
      expect(iso_a2).to eq('US')
      expect(iso_a3).to eq('USA')
    end

    it 'returns nil for unknown country names' do
      iso_a2, iso_a3 = described_class.iso_codes_from_country_name('Atlantis')
      expect(iso_a2).to be_nil
      expect(iso_a3).to be_nil
    end

    it 'returns nil for blank input' do
      iso_a2, iso_a3 = described_class.iso_codes_from_country_name('')
      expect(iso_a2).to be_nil
      expect(iso_a3).to be_nil

      iso_a2, iso_a3 = described_class.iso_codes_from_country_name(nil)
      expect(iso_a2).to be_nil
      expect(iso_a3).to be_nil
    end
  end

  describe '.fallback_codes_from_country_name' do
    it 'returns proper ISO codes when country name is recognized' do
      iso_a2, iso_a3 = described_class.fallback_codes_from_country_name('Germany')
      expect(iso_a2).to eq('DE')
      expect(iso_a3).to eq('DEU')
    end

    it 'falls back to character-based codes for unknown countries' do
      iso_a2, iso_a3 = described_class.fallback_codes_from_country_name('Atlantis')
      expect(iso_a2).to eq('AT')
      expect(iso_a3).to eq('ATL')
    end

    it 'returns nil for blank input' do
      iso_a2, iso_a3 = described_class.fallback_codes_from_country_name('')
      expect(iso_a2).to be_nil
      expect(iso_a3).to be_nil

      iso_a2, iso_a3 = described_class.fallback_codes_from_country_name(nil)
      expect(iso_a2).to be_nil
      expect(iso_a3).to be_nil
    end
  end

  describe '.standardize_country_name' do
    it 'returns standard name for exact match' do
      expect(described_class.standardize_country_name('Germany')).to eq('Germany')
    end

    it 'returns standard name for aliases' do
      expect(described_class.standardize_country_name('Russia')).to eq('Russian Federation')
      expect(described_class.standardize_country_name('USA')).to eq('United States')
    end

    it 'handles case-insensitive matching' do
      expect(described_class.standardize_country_name('GERMANY')).to eq('Germany')
      expect(described_class.standardize_country_name('germany')).to eq('Germany')
    end

    it 'returns nil for unknown country names' do
      expect(described_class.standardize_country_name('Atlantis')).to be_nil
    end

    it 'returns nil for blank input' do
      expect(described_class.standardize_country_name('')).to be_nil
      expect(described_class.standardize_country_name(nil)).to be_nil
    end
  end

  describe '.country_flag' do
    it 'returns correct flag emoji for valid ISO A2 code' do
      expect(described_class.country_flag('DE')).to eq('🇩🇪')
      expect(described_class.country_flag('US')).to eq('🇺🇸')
      expect(described_class.country_flag('GB')).to eq('🇬🇧')
    end

    it 'handles lowercase input' do
      expect(described_class.country_flag('de')).to eq('🇩🇪')
    end

    it 'returns nil for invalid ISO A2 code' do
      expect(described_class.country_flag('XX')).to be_nil
      expect(described_class.country_flag('')).to be_nil
      expect(described_class.country_flag(nil)).to be_nil
    end
  end

  describe '.country_by_iso2' do
    it 'returns complete country data for valid ISO A2 code' do
      country = described_class.country_by_iso2('DE')
      expect(country).to include(
        name: 'Germany',
        iso2: 'DE',
        iso3: 'DEU',
        flag: '🇩🇪'
      )
    end

    it 'handles lowercase input' do
      country = described_class.country_by_iso2('de')
      expect(country[:name]).to eq('Germany')
    end

    it 'returns nil for invalid ISO A2 code' do
      expect(described_class.country_by_iso2('XX')).to be_nil
      expect(described_class.country_by_iso2('')).to be_nil
      expect(described_class.country_by_iso2(nil)).to be_nil
    end
  end

  describe '.country_by_name' do
    it 'returns complete country data for exact name match' do
      country = described_class.country_by_name('Germany')
      expect(country).to include(
        name: 'Germany',
        iso2: 'DE',
        iso3: 'DEU',
        flag: '🇩🇪'
      )
    end

    it 'returns country data for aliases' do
      country = described_class.country_by_name('Russia')
      expect(country).to include(
        name: 'Russian Federation',
        iso2: 'RU',
        iso3: 'RUS',
        flag: '🇷🇺'
      )
    end

    it 'handles case-insensitive matching' do
      country = described_class.country_by_name('GERMANY')
      expect(country[:name]).to eq('Germany')
    end

    it 'returns nil for unknown country names' do
      expect(described_class.country_by_name('Atlantis')).to be_nil
    end

    it 'returns nil for blank input' do
      expect(described_class.country_by_name('')).to be_nil
      expect(described_class.country_by_name(nil)).to be_nil
    end
  end

  describe '.all_countries' do
    it 'returns all country data' do
      countries = described_class.all_countries
      expect(countries).to be_an(Array)
      expect(countries.size).to be > 190  # There are 195+ countries

      # Check that each country has required fields
      countries.each do |country|
        expect(country).to have_key(:name)
        expect(country).to have_key(:iso2)
        expect(country).to have_key(:iso3)
        expect(country).to have_key(:flag)
      end
    end

    it 'includes expected countries' do
      countries = described_class.all_countries
      country_names = countries.map { |c| c[:name] }

      expect(country_names).to include('Germany')
      expect(country_names).to include('United States')
      expect(country_names).to include('United Kingdom')
      expect(country_names).to include('Russian Federation')
    end
  end

  describe 'data integrity' do
    it 'has consistent data structure' do
      described_class.all_countries.each do |country|
        expect(country[:iso2]).to match(/\A[A-Z]{2}\z/)
        expect(country[:iso3]).to match(/\A[A-Z]{3}\z/)
        expect(country[:name]).to be_present
        expect(country[:flag]).to be_present
      end
    end

    it 'has unique ISO codes' do
      iso2_codes = described_class.all_countries.map { |c| c[:iso2] }
      iso3_codes = described_class.all_countries.map { |c| c[:iso3] }

      expect(iso2_codes.uniq.size).to eq(iso2_codes.size)
      expect(iso3_codes.uniq.size).to eq(iso3_codes.size)
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Residency::DayCounter do
  describe '#call' do
    let(:user) { create(:user) }
    let(:year) { 2025 }

    subject(:result) { described_class.new(user, year).call }

    context 'when user has no points' do
      it 'returns empty countries array' do
        expect(result[:countries]).to eq([])
        expect(result[:year]).to eq(2025)
        expect(result[:total_tracked_days]).to eq(0)
      end
    end

    context 'when user has points in one country' do
      before do
        # 3 consecutive days in Germany
        [1, 2, 3].each do |day|
          create(:point,
                 user:,
                 country_name: 'Germany',
                 timestamp: Time.zone.local(2025, 1, day, 12, 0).to_i)
        end
      end

      it 'counts days correctly' do
        germany = result[:countries].find { |c| c[:country_name] == 'Germany' }

        expect(germany[:days]).to eq(3)
        expect(germany[:percentage]).to eq(100.0)
      end

      it 'groups consecutive days into periods' do
        germany = result[:countries].find { |c| c[:country_name] == 'Germany' }

        expect(germany[:periods].size).to eq(1)
        expect(germany[:periods].first[:start_date]).to eq('2025-01-01')
        expect(germany[:periods].first[:end_date]).to eq('2025-01-03')
        expect(germany[:periods].first[:consecutive_days]).to eq(3)
      end
    end

    context 'when user has points in multiple countries' do
      before do
        # 5 days in Germany (Jan 1-5)
        (1..5).each do |day|
          create(:point,
                 user:,
                 country_name: 'Germany',
                 timestamp: Time.zone.local(2025, 1, day, 12, 0).to_i)
        end

        # 3 days in France (Jan 10-12)
        (10..12).each do |day|
          create(:point,
                 user:,
                 country_name: 'France',
                 timestamp: Time.zone.local(2025, 1, day, 12, 0).to_i)
        end
      end

      it 'counts days per country' do
        germany = result[:countries].find { |c| c[:country_name] == 'Germany' }
        france = result[:countries].find { |c| c[:country_name] == 'France' }

        expect(germany[:days]).to eq(5)
        expect(france[:days]).to eq(3)
      end

      it 'sorts by days descending' do
        expect(result[:countries].first[:country_name]).to eq('Germany')
        expect(result[:countries].last[:country_name]).to eq('France')
      end

      it 'calculates total tracked days' do
        expect(result[:total_tracked_days]).to eq(8)
      end

      it 'calculates percentages based on total tracked days' do
        germany = result[:countries].find { |c| c[:country_name] == 'Germany' }
        france = result[:countries].find { |c| c[:country_name] == 'France' }

        expect(germany[:percentage]).to eq(62.5) # 5/8
        expect(france[:percentage]).to eq(37.5) # 3/8
      end
    end

    context 'when user visits the same country in multiple separate periods' do
      before do
        # Period 1: Jan 1-3
        (1..3).each do |day|
          create(:point,
                 user:,
                 country_name: 'Germany',
                 timestamp: Time.zone.local(2025, 1, day, 12, 0).to_i)
        end

        # Period 2: Jan 10-15
        (10..15).each do |day|
          create(:point,
                 user:,
                 country_name: 'Germany',
                 timestamp: Time.zone.local(2025, 1, day, 12, 0).to_i)
        end
      end

      it 'creates separate periods for non-consecutive stays' do
        germany = result[:countries].find { |c| c[:country_name] == 'Germany' }

        expect(germany[:days]).to eq(9)
        expect(germany[:periods].size).to eq(2)
        expect(germany[:periods][0][:consecutive_days]).to eq(3)
        expect(germany[:periods][1][:consecutive_days]).to eq(6)
      end
    end

    context 'when the user timezone differs from the application timezone' do
      let(:user) { create(:user, settings: { 'timezone' => 'Pacific/Auckland' }) }

      before do
        # Auckland is UTC+13 in summer: these are local January 1, 2025 and January 1, 2026.
        create(:point, user:, country_name: 'New Zealand', timestamp: Time.utc(2024, 12, 31, 12).to_i)
        create(:point, user:, country_name: 'New Zealand', timestamp: Time.utc(2025, 12, 31, 12).to_i)
      end

      it 'buckets days and year bounds in the user timezone' do
        expect(result[:daily_countries]).to eq('2025-01-01' => 'New Zealand')
        expect(result[:countries].first[:periods]).to eq(
          [{ start_date: '2025-01-01', end_date: '2025-01-01', consecutive_days: 1 }]
        )
      end
    end

    context 'when a day has points in multiple countries (multi-country day)' do
      before do
        # Same day, two countries
        create(:point,
               user:,
               country_name: 'Germany',
               timestamp: Time.zone.local(2025, 3, 15, 8, 0).to_i)
        create(:point,
               user:,
               country_name: 'France',
               timestamp: Time.zone.local(2025, 3, 15, 18, 0).to_i)
      end

      it 'counts the day for each country (any-presence mode)' do
        germany = result[:countries].find { |c| c[:country_name] == 'Germany' }
        france = result[:countries].find { |c| c[:country_name] == 'France' }

        expect(germany[:days]).to eq(1)
        expect(france[:days]).to eq(1)
      end

      it 'total_tracked_days counts distinct calendar days' do
        expect(result[:total_tracked_days]).to eq(1)
      end
    end

    context 'when a country exceeds 183-day threshold' do
      before do
        # Create 184 days in Germany
        (1..184).each do |i|
          date = Date.new(2025, 1, 1) + (i - 1).days
          create(:point,
                 user:,
                 country_name: 'Germany',
                 timestamp: Time.zone.local(date.year, date.month, date.day, 12, 0).to_i)
        end
      end

      it 'sets threshold_warning to true' do
        germany = result[:countries].find { |c| c[:country_name] == 'Germany' }

        expect(germany[:threshold_warning]).to be true
      end
    end

    context 'when a country has exactly 182 days' do
      before do
        (1..182).each do |i|
          date = Date.new(2025, 1, 1) + (i - 1).days
          create(:point,
                 user:,
                 country_name: 'Germany',
                 timestamp: Time.zone.local(date.year, date.month, date.day, 12, 0).to_i)
        end
      end

      it 'does not set threshold_warning' do
        germany = result[:countries].find { |c| c[:country_name] == 'Germany' }

        expect(germany[:threshold_warning]).to be false
      end
    end

    context 'when points carry aliased spellings of the same country' do
      # Geocoded points store the OSM name ("United States") while points
      # resolved against the countries table store the Natural Earth name
      # ("United States of America"). They are the same country and must be
      # counted together, otherwise one country is split across two rows and
      # can fall below the 183-day residency threshold.
      before do
        [1, 2, 3].each do |day|
          create(:point,
                 user:,
                 country_name: 'United States',
                 timestamp: Time.zone.local(2025, 1, day, 12, 0).to_i)
        end

        create(:point,
               user:,
               country_name: 'United States of America',
               timestamp: Time.zone.local(2025, 1, 4, 12, 0).to_i)
      end

      it 'reports a single country' do
        expect(result[:countries].map { |c| c[:country_name] }).to eq(['United States of America'])
      end

      it 'sums days across both spellings' do
        expect(result[:countries].first[:days]).to eq(4)
      end

      it 'resolves each day to the canonical country name' do
        expect(result[:daily_countries].values.uniq).to eq(['United States of America'])
      end
    end

    context 'when one country is stored under different names' do
      let(:noon) { Time.zone.local(2025, 3, 1, 12, 0).to_i }

      it 'counts a day holding both spellings once' do
        create(:point, user:, country_name: 'United States', timestamp: noon)
        create(:point, user:, country_name: 'United States of America', timestamp: noon + 1.hour.to_i)

        expect(result[:countries].map { |c| [c[:country_name], c[:days]] })
          .to eq([['United States of America', 1]])
        expect(result[:total_tracked_days]).to eq(1)
      end

      it 'reaches the residency threshold with 100 days under each spelling' do
        (0...200).each do |offset|
          create(:point, user:, country_name: offset < 100 ? 'United States' : 'United States of America',
                         timestamp: noon + offset.days.to_i)
        end

        country = result[:countries].sole
        expect(country).to include(days: 200, threshold_warning: true)
      end

      it 'groups by the linked country before looking at the stored text' do
        germany = create(:country, name: 'Germany', iso_a2: 'DE', iso_a3: 'DEU')
        create(:point, user:, country_name: 'Deutschland', timestamp: noon).update_columns(country_id: germany.id)
        create(:point, user:, country_name: 'Germany', timestamp: noon + 1.day.to_i)

        expect(result[:countries].map { |c| [c[:country_name], c[:days]] }).to eq([['Germany', 2]])
      end

      it 'passes a name it does not know through unchanged' do
        create(:point, user:, country_name: 'Atlantis', timestamp: noon)

        expect(result[:countries].sole).to include(country_name: 'Atlantis', iso_a2: nil, flag: nil)
      end

      it 'leaves points without a country name out' do
        create(:point, user:, country_name: nil, timestamp: noon)

        expect(result[:countries]).to eq([])
      end

      it 'keeps a flown-over country out under its aliased spelling' do
        create(:point, user:, country_name: 'United States', velocity: 250, timestamp: noon)
        create(:point, user:, country_name: 'France', timestamp: noon + 1.day.to_i)

        expect(result[:countries].map { |c| c[:country_name] }).to eq(['France'])
      end

      {
        'Tanzania' => ['United Republic of Tanzania', 'TZ', 'TZA'],
        'Cape Verde' => ['Cabo Verde', 'CV', 'CPV'],
        'Saint Barthélemy' => ['Saint Barthelemy', 'BL', 'BLM'],
        'Congo-Kinshasa' => ['Democratic Republic of the Congo', 'CD', 'COD'],
        'São Tomé and Príncipe' => ['São Tomé and Principe', 'ST', 'STP'],
        'Eswatini' => %w[eSwatini SZ SWZ]
      }.each do |spelling, (seeded_name, iso_a2, iso_a3)|
        it "shows the code and flag of #{seeded_name}" do
          create(:country, name: seeded_name, iso_a2:, iso_a3:)
          create(:point, user:, country_name: spelling, timestamp: noon)

          expect(result[:countries].sole).to include(
            country_name: seeded_name,
            iso_a2:,
            flag: Countries::IsoCodeMapper.country_flag(iso_a2)
          )
        end
      end
    end

    context 'when points have blank country_name' do
      before do
        create(:point, user:, country_name: '', timestamp: Time.zone.local(2025, 1, 1, 12, 0).to_i)
        create(:point, user:, country_name: nil, timestamp: Time.zone.local(2025, 1, 2, 12, 0).to_i)
        create(:point, user:, country_name: 'Germany', timestamp: Time.zone.local(2025, 1, 3, 12, 0).to_i)
      end

      it 'excludes points without country_name' do
        expect(result[:countries].size).to eq(1)
        expect(result[:countries].first[:country_name]).to eq('Germany')
        expect(result[:countries].first[:days]).to eq(1)
      end
    end

    context 'iso_a2 and flag fields' do
      before do
        create(:point,
               user:,
               country_name: 'Germany',
               timestamp: Time.zone.local(2025, 6, 1, 12, 0).to_i)
      end

      it 'includes iso_a2 code' do
        germany = result[:countries].first
        # iso_a2 comes from Country.names_to_iso_a2 or IsoCodeMapper
        expect(germany).to have_key(:iso_a2)
      end

      it 'includes flag emoji' do
        germany = result[:countries].first
        expect(germany).to have_key(:flag)
      end
    end

    describe '#available_years' do
      before do
        create(:stat, user:, year: 2023, month: 1)
        create(:stat, user:, year: 2024, month: 1)
        create(:stat, user:, year: 2025, month: 1)
      end

      it 'returns years from user stats sorted ascending' do
        expect(result[:available_years]).to eq([2023, 2024, 2025])
      end
    end
  end
end

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

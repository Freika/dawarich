# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Insights::ActivityHeatmapCalculator do
  let(:user) { create(:user) }
  let(:year) { 2024 }

  describe '#call' do
    context 'with no stats' do
      let(:stats) { Stat.none }

      it 'returns empty result' do
        result = described_class.new(stats, year).call

        expect(result.daily_data).to eq({})
        expect(result.active_days).to eq(0)
        expect(result.max_distance).to eq(0)
        expect(result.year).to eq(year)
      end

      it 'returns default activity levels' do
        result = described_class.new(stats, year).call

        expect(result.activity_levels).to eq({ p25: 1000, p50: 5000, p75: 10_000, p90: 20_000 })
      end
    end

    context 'with stats containing daily_distance as hash' do
      let!(:january_stat) do
        create(:stat, user: user, year: year, month: 1,
               daily_distance: { '1' => 5000, '2' => 10_000, '15' => 3000 })
      end
      let!(:february_stat) do
        create(:stat, user: user, year: year, month: 2,
               daily_distance: { '1' => 8000, '28' => 12_000 })
      end
      let(:stats) { user.stats.where(year: year) }

      it 'aggregates daily distances into date-keyed hash' do
        result = described_class.new(stats, year).call

        expect(result.daily_data['2024-01-01']).to eq(5000)
        expect(result.daily_data['2024-01-02']).to eq(10_000)
        expect(result.daily_data['2024-01-15']).to eq(3000)
        expect(result.daily_data['2024-02-01']).to eq(8000)
        expect(result.daily_data['2024-02-28']).to eq(12_000)
      end

      it 'calculates active days count' do
        result = described_class.new(stats, year).call

        expect(result.active_days).to eq(5)
      end

      it 'finds max distance' do
        result = described_class.new(stats, year).call

        expect(result.max_distance).to eq(12_000)
      end

      it 'returns the year' do
        result = described_class.new(stats, year).call

        expect(result.year).to eq(year)
      end
    end

    context 'with stats containing daily_distance as array' do
      let!(:stat) do
        create(:stat, user: user, year: year, month: 3,
               daily_distance: [[1, 5000], [2, 7500], [10, 2000]])
      end
      let(:stats) { user.stats.where(year: year) }

      it 'handles array format correctly' do
        result = described_class.new(stats, year).call

        expect(result.daily_data['2024-03-01']).to eq(5000)
        expect(result.daily_data['2024-03-02']).to eq(7500)
        expect(result.daily_data['2024-03-10']).to eq(2000)
        expect(result.active_days).to eq(3)
      end
    end

    context 'with days with zero distance' do
      let!(:stat) do
        create(:stat, user: user, year: year, month: 4,
               daily_distance: { '1' => 5000, '2' => 0, '3' => 3000 })
      end
      let(:stats) { user.stats.where(year: year) }

      it 'excludes zero-distance days from active days count' do
        result = described_class.new(stats, year).call

        expect(result.active_days).to eq(2)
      end

      it 'excludes zero-distance days from activity level calculation' do
        result = described_class.new(stats, year).call

        # Only 5000 and 3000 should be considered
        expect(result.max_distance).to eq(5000)
      end
    end

    context 'with invalid day numbers' do
      let!(:stat) do
        create(:stat, user: user, year: year, month: 2,
               daily_distance: { '1' => 5000, '30' => 10_000 }) # Feb doesn't have day 30
      end
      let(:stats) { user.stats.where(year: year) }

      it 'skips invalid dates gracefully' do
        result = described_class.new(stats, year).call

        expect(result.daily_data.keys).to eq(['2024-02-01'])
        expect(result.active_days).to eq(1)
      end
    end

    context 'activity level calculation' do
      let!(:stat) do
        # Create 10 days with varying distances
        distances = (1..10).map { |day| [day.to_s, day * 1000] }.to_h
        create(:stat, user: user, year: year, month: 5, daily_distance: distances)
      end
      let(:stats) { user.stats.where(year: year) }

      it 'calculates percentile-based activity levels' do
        result = described_class.new(stats, year).call

        # With values 1000-10000, percentiles should be calculated
        expect(result.activity_levels[:p25]).to be_a(Integer)
        expect(result.activity_levels[:p50]).to be_a(Integer)
        expect(result.activity_levels[:p75]).to be_a(Integer)
        expect(result.activity_levels[:p90]).to be_a(Integer)

        # Levels should be in ascending order
        expect(result.activity_levels[:p25]).to be <= result.activity_levels[:p50]
        expect(result.activity_levels[:p50]).to be <= result.activity_levels[:p75]
        expect(result.activity_levels[:p75]).to be <= result.activity_levels[:p90]
      end
    end

    context 'with leap year' do
      let(:leap_year) { 2024 }
      let!(:stat) do
        create(:stat, user: user, year: leap_year, month: 2,
               daily_distance: { '29' => 5000 }) # Feb 29 only exists in leap years
      end
      let(:stats) { user.stats.where(year: leap_year) }

      it 'handles leap year correctly' do
        result = described_class.new(stats, leap_year).call

        expect(result.daily_data['2024-02-29']).to eq(5000)
        expect(result.active_days).to eq(1)
      end
    end

    context 'streak calculation' do
      context 'with consecutive days' do
        let!(:stat) do
          create(:stat, user: user, year: year, month: 1,
                 daily_distance: { '1' => 5000, '2' => 6000, '3' => 7000, '4' => 8000, '5' => 9000 })
        end
        let(:stats) { user.stats.where(year: year) }

        it 'calculates longest streak correctly' do
          result = described_class.new(stats, year).call

          expect(result.longest_streak).to eq(5)
          expect(result.longest_streak_start).to eq(Date.new(2024, 1, 1))
          expect(result.longest_streak_end).to eq(Date.new(2024, 1, 5))
        end
      end

      context 'with gaps between active days' do
        let!(:stat) do
          create(:stat, user: user, year: year, month: 1,
                 daily_distance: { '1' => 5000, '2' => 6000, '5' => 7000, '6' => 8000, '7' => 9000 })
        end
        let(:stats) { user.stats.where(year: year) }

        it 'finds the longest consecutive streak' do
          result = described_class.new(stats, year).call

          expect(result.longest_streak).to eq(3)
          expect(result.longest_streak_start).to eq(Date.new(2024, 1, 5))
          expect(result.longest_streak_end).to eq(Date.new(2024, 1, 7))
        end
      end

      context 'with streak spanning months' do
        let!(:january_stat) do
          create(:stat, user: user, year: year, month: 1,
                 daily_distance: { '30' => 5000, '31' => 6000 })
        end
        let!(:february_stat) do
          create(:stat, user: user, year: year, month: 2,
                 daily_distance: { '1' => 7000, '2' => 8000 })
        end
        let(:stats) { user.stats.where(year: year) }

        it 'counts streak across month boundaries' do
          result = described_class.new(stats, year).call

          expect(result.longest_streak).to eq(4)
          expect(result.longest_streak_start).to eq(Date.new(2024, 1, 30))
          expect(result.longest_streak_end).to eq(Date.new(2024, 2, 2))
        end
      end

      context 'with no stats' do
        let(:stats) { Stat.none }

        it 'returns zero streaks' do
          result = described_class.new(stats, year).call

          expect(result.current_streak).to eq(0)
          expect(result.longest_streak).to eq(0)
          expect(result.longest_streak_start).to be_nil
          expect(result.longest_streak_end).to be_nil
        end
      end

      context 'with single active day' do
        let!(:stat) do
          create(:stat, user: user, year: year, month: 6,
                 daily_distance: { '15' => 5000 })
        end
        let(:stats) { user.stats.where(year: year) }

        it 'returns streak of 1' do
          result = described_class.new(stats, year).call

          expect(result.longest_streak).to eq(1)
          expect(result.longest_streak_start).to eq(Date.new(2024, 6, 15))
          expect(result.longest_streak_end).to eq(Date.new(2024, 6, 15))
        end
      end
    end
  end
end

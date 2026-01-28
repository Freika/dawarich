# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Insights::TravelPatternsLoader do
  describe '#call' do
    subject(:loader) do
      described_class.new(user, year, month, monthly_digest: monthly_digest)
    end

    let(:user) { create(:user) }
    let(:year) { 2024 }
    let(:month) { 6 } # June has 30 days
    let(:monthly_digest) { nil }

    # Valid monthly_distances for June (30 days)
    let(:june_monthly_distances) do
      (1..30).map { |day| [day, day * 1000] }
    end

    context 'when monthly digest exists with all data' do
      let(:time_of_day_data) { [10, 20, 30, 40, 50, 60, 70, 80] }
      let(:activity_breakdown_data) do
        { 'walking' => 40, 'driving' => 35, 'cycling' => 25 }
      end

      let(:monthly_digest) do
        create(:users_digest, :monthly,
               user: user,
               year: year,
               month: month,
               travel_patterns: {
                 'time_of_day' => time_of_day_data,
                 'activity_breakdown' => activity_breakdown_data
               },
               monthly_distances: june_monthly_distances)
      end

      it 'loads time_of_day from digest' do
        result = loader.call

        expect(result.time_of_day).to eq(time_of_day_data)
      end

      it 'loads day_of_week from digest (calculated from daily distances)' do
        result = loader.call

        # weekly_pattern is calculated from daily_distances, not stored
        expect(result.day_of_week).to be_an(Array)
        expect(result.day_of_week.length).to eq(7)
      end

      it 'loads activity_breakdown from digest' do
        result = loader.call

        expect(result.activity_breakdown).to eq(activity_breakdown_data)
      end
    end

    context 'when monthly digest has no time_of_day' do
      let(:monthly_digest) do
        create(:users_digest, :monthly,
               user: user,
               year: year,
               month: month,
               travel_patterns: {},
               monthly_distances: june_monthly_distances)
      end

      let(:calculated_time_of_day) { [5, 10, 15, 20, 25, 30, 35, 40] }

      before do
        time_of_day_query = instance_double(Stats::TimeOfDayQuery)
        allow(Stats::TimeOfDayQuery).to receive(:new)
          .with(user, year, month, user.timezone)
          .and_return(time_of_day_query)
        allow(time_of_day_query).to receive(:call).and_return(calculated_time_of_day)
      end

      it 'calculates time_of_day on demand' do
        result = loader.call

        expect(result.time_of_day).to eq(calculated_time_of_day)
      end
    end

    context 'when monthly digest has no daily distances for weekly_pattern' do
      let(:monthly_digest) do
        create(:users_digest, :monthly,
               user: user,
               year: year,
               month: month,
               monthly_distances: [])
      end

      it 'returns default array of zeros' do
        result = loader.call

        expect(result.day_of_week).to eq(Array.new(7, 0))
      end
    end

    context 'when monthly digest has no activity_breakdown' do
      let(:monthly_digest) do
        create(:users_digest, :monthly,
               user: user,
               year: year,
               month: month,
               travel_patterns: {},
               monthly_distances: june_monthly_distances)
      end

      let(:calculated_breakdown) { { 'walking' => 60, 'stationary' => 40 } }

      before do
        calculator = instance_double(Users::Digests::ActivityBreakdownCalculator)
        allow(Users::Digests::ActivityBreakdownCalculator).to receive(:new)
          .with(user, year, month)
          .and_return(calculator)
        allow(calculator).to receive(:call).and_return(calculated_breakdown)
      end

      it 'calculates activity_breakdown on demand' do
        result = loader.call

        expect(result.activity_breakdown).to eq(calculated_breakdown)
      end
    end

    context 'when no monthly digest exists' do
      let(:monthly_digest) { nil }
      let(:calculated_time_of_day) { [1, 2, 3, 4, 5, 6, 7, 8] }
      let(:calculated_breakdown) { { 'driving' => 100 } }

      before do
        time_of_day_query = instance_double(Stats::TimeOfDayQuery)
        allow(Stats::TimeOfDayQuery).to receive(:new)
          .with(user, year, month, user.timezone)
          .and_return(time_of_day_query)
        allow(time_of_day_query).to receive(:call).and_return(calculated_time_of_day)

        calculator = instance_double(Users::Digests::ActivityBreakdownCalculator)
        allow(Users::Digests::ActivityBreakdownCalculator).to receive(:new)
          .with(user, year, month)
          .and_return(calculator)
        allow(calculator).to receive(:call).and_return(calculated_breakdown)
      end

      it 'calculates all data on demand' do
        result = loader.call

        expect(result.time_of_day).to eq(calculated_time_of_day)
        expect(result.day_of_week).to eq(Array.new(7, 0))
        expect(result.activity_breakdown).to eq(calculated_breakdown)
      end
    end

    context 'when loading seasonality' do
      context 'when yearly digest has seasonality in travel_patterns' do
        let(:seasonality_data) { { 'spring' => 25, 'summer' => 35, 'fall' => 25, 'winter' => 15 } }

        before do
          create(:users_digest,
                 user: user,
                 year: year,
                 period_type: :yearly,
                 travel_patterns: { 'seasonality' => seasonality_data })
        end

        it 'loads seasonality from yearly digest' do
          result = loader.call

          expect(result.seasonality).to eq(seasonality_data)
        end
      end

      context 'when yearly digest has no seasonality' do
        let(:calculated_seasonality) { { 'spring' => 20, 'summer' => 40, 'fall' => 30, 'winter' => 10 } }

        before do
          create(:users_digest,
                 user: user,
                 year: year,
                 period_type: :yearly,
                 travel_patterns: {})

          calculator = instance_double(Users::Digests::SeasonalityCalculator)
          allow(Users::Digests::SeasonalityCalculator).to receive(:new)
            .with(user, year)
            .and_return(calculator)
          allow(calculator).to receive(:call).and_return(calculated_seasonality)
        end

        it 'calculates seasonality on demand' do
          result = loader.call

          expect(result.seasonality).to eq(calculated_seasonality)
        end
      end

      context 'when no yearly digest exists' do
        let(:calculated_seasonality) { { 'spring' => 50, 'summer' => 50 } }

        before do
          calculator = instance_double(Users::Digests::SeasonalityCalculator)
          allow(Users::Digests::SeasonalityCalculator).to receive(:new)
            .with(user, year)
            .and_return(calculator)
          allow(calculator).to receive(:call).and_return(calculated_seasonality)
        end

        it 'calculates seasonality on demand' do
          result = loader.call

          expect(result.seasonality).to eq(calculated_seasonality)
        end
      end
    end
  end
end

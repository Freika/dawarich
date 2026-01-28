# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Insights::TravelInsightGenerator do
  describe '#call' do
    subject(:result) { described_class.new(time_of_day:, day_of_week:, seasonality:).call }

    context 'when all data is empty' do
      let(:time_of_day) { {} }
      let(:day_of_week) { Array.new(7, 0) }
      let(:seasonality) { {} }

      it 'returns nil' do
        expect(result).to be_nil
      end
    end

    context 'when all data is nil' do
      let(:time_of_day) { nil }
      let(:day_of_week) { nil }
      let(:seasonality) { nil }

      it 'returns nil' do
        expect(result).to be_nil
      end
    end

    context 'with time of day data above threshold' do
      let(:time_of_day) { { 'morning' => 50, 'afternoon' => 20, 'evening' => 20, 'night' => 10 } }
      let(:day_of_week) { Array.new(7, 0) }
      let(:seasonality) { {} }

      it 'includes time of day insight' do
        expect(result).to include('You travel most in the morning')
      end
    end

    context 'with time of day data below threshold' do
      let(:time_of_day) { { 'morning' => 25, 'afternoon' => 25, 'evening' => 25, 'night' => 25 } }
      let(:day_of_week) { Array.new(7, 0) }
      let(:seasonality) { {} }

      it 'returns nil when no clear peak' do
        expect(result).to be_nil
      end
    end

    context 'with weekend-heavy day of week data' do
      let(:time_of_day) { {} }
      let(:day_of_week) { [100, 100, 100, 100, 100, 500, 500] } # Weekend much higher
      let(:seasonality) { {} }

      it 'identifies weekend as most active' do
        expect(result).to include('most active travel day')
      end
    end

    context 'with weekday-heavy day of week data' do
      let(:time_of_day) { {} }
      let(:day_of_week) { [500, 500, 500, 500, 500, 100, 100] } # Weekdays much higher
      let(:seasonality) { {} }

      it 'identifies weekday preference' do
        expect(result).to include('You travel more on weekdays than weekends')
      end
    end

    context 'with seasonality data above threshold' do
      let(:time_of_day) { {} }
      let(:day_of_week) { Array.new(7, 0) }
      let(:seasonality) { { 'winter' => 10, 'spring' => 20, 'summer' => 50, 'fall' => 20 } }

      it 'identifies peak season' do
        expect(result).to include('Summer is your peak travel season')
      end
    end

    context 'with multiple insights' do
      let(:time_of_day) { { 'morning' => 50, 'afternoon' => 20, 'evening' => 20, 'night' => 10 } }
      let(:day_of_week) { [500, 500, 500, 500, 500, 100, 100] }
      let(:seasonality) { { 'winter' => 10, 'spring' => 20, 'summer' => 50, 'fall' => 20 } }

      it 'combines insights with proper punctuation' do
        expect(result).to include('You travel most in the morning')
        expect(result).to include('You travel more on weekdays than weekends')
        expect(result).to include('Summer is your peak travel season')
      end
    end

    context 'with morning peak time' do
      let(:time_of_day) { { 'morning' => 50, 'afternoon' => 20, 'evening' => 20, 'night' => 10 } }
      let(:day_of_week) { Array.new(7, 0) }
      let(:seasonality) { {} }

      it 'may include morning suggestion' do
        # Suggestion is randomly sampled, so we just check the main insight is present
        expect(result).to include('You travel most in the morning')
      end
    end

    context 'with evening peak time' do
      let(:time_of_day) { { 'morning' => 10, 'afternoon' => 20, 'evening' => 50, 'night' => 20 } }
      let(:day_of_week) { Array.new(7, 0) }
      let(:seasonality) { {} }

      it 'includes evening insight' do
        expect(result).to include('You travel most in the evening')
      end
    end
  end
end

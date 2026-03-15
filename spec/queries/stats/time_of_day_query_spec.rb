# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Stats::TimeOfDayQuery do
  let(:user) { create(:user) }
  let(:year) { 2021 }

  describe '#call' do
    context 'with timezone-driven classification' do
      let(:month) { 1 }

      # One point at 10:00 UTC on Jan 15
      let!(:point) do
        create(:point, user: user, timestamp: DateTime.new(2021, 1, 15, 10, 0, 0).to_i)
      end

      context 'in Etc/UTC (10:00 → morning)' do
        subject { described_class.new(user, year, month, 'Etc/UTC').call }

        it 'classifies the point as morning' do
          expect(subject['morning']).to eq(100)
          expect(subject['evening']).to eq(0)
          expect(subject['night']).to eq(0)
          expect(subject['afternoon']).to eq(0)
        end
      end

      context 'in Asia/Tokyo (+9, 10:00 UTC → 19:00 → evening)' do
        subject { described_class.new(user, year, month, 'Asia/Tokyo').call }

        it 'classifies the point as evening' do
          expect(subject['evening']).to eq(100)
          expect(subject['morning']).to eq(0)
        end
      end

      context 'in America/New_York (-5, 10:00 UTC → 05:00 → night)' do
        subject { described_class.new(user, year, month, 'America/New_York').call }

        it 'classifies the point as night' do
          expect(subject['night']).to eq(100)
          expect(subject['morning']).to eq(0)
        end
      end
    end

    context 'with percentage normalization' do
      let(:month) { 2 }

      # 3 morning points + 1 afternoon point
      let!(:morning_points) do
        3.times.map do |i|
          create(:point, user: user, timestamp: DateTime.new(2021, 2, 1, 8, i * 10, 0).to_i)
        end
      end
      let!(:afternoon_point) do
        create(:point, user: user, timestamp: DateTime.new(2021, 2, 1, 14, 0, 0).to_i)
      end

      subject { described_class.new(user, year, month, 'Etc/UTC').call }

      it 'returns 75% morning and 25% afternoon' do
        expect(subject['morning']).to eq(75)
        expect(subject['afternoon']).to eq(25)
        expect(subject['night']).to eq(0)
        expect(subject['evening']).to eq(0)
      end
    end

    context 'with no points' do
      let(:month) { 3 }

      subject { described_class.new(user, year, month, 'Etc/UTC').call }

      it 'returns all zeros' do
        expect(subject).to eq(
          'night' => 0, 'morning' => 0, 'afternoon' => 0, 'evening' => 0
        )
      end
    end

    context 'with year scope (month=nil)' do
      # Point in January and one in June
      let!(:jan_point) do
        create(:point, user: user, timestamp: DateTime.new(2021, 1, 15, 9, 0, 0).to_i)
      end
      let!(:jun_point) do
        create(:point, user: user, timestamp: DateTime.new(2021, 6, 15, 15, 0, 0).to_i)
      end

      subject { described_class.new(user, year, nil, 'Etc/UTC').call }

      it 'includes points across all months' do
        expect(subject['morning']).to eq(50)
        expect(subject['afternoon']).to eq(50)
      end
    end
  end

  describe '#validate_timezone' do
    let(:month) { 1 }

    subject { described_class.new(user, year, month, timezone).send(:timezone) }

    context 'with IANA identifier' do
      let(:timezone) { 'Europe/Berlin' }

      it 'accepts and returns the IANA name' do
        expect(subject).to eq('Europe/Berlin')
      end
    end

    context 'with ActiveSupport short name' do
      let(:timezone) { 'Berlin' }

      it 'converts to IANA identifier' do
        expect(subject).to eq('Europe/Berlin')
      end
    end

    context 'with UTC' do
      let(:timezone) { 'UTC' }

      it 'returns Etc/UTC' do
        expect(subject).to eq('Etc/UTC')
      end
    end

    context 'with invalid string' do
      let(:timezone) { 'Not/A/Timezone' }

      it 'falls back to Etc/UTC' do
        expect(subject).to eq('Etc/UTC')
      end
    end

    context 'with nil' do
      let(:timezone) { nil }

      it 'falls back to Etc/UTC' do
        expect(subject).to eq('Etc/UTC')
      end
    end

    context 'with empty string' do
      let(:timezone) { '' }

      it 'falls back to Etc/UTC' do
        expect(subject).to eq('Etc/UTC')
      end
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Stats::DailyDistanceQuery do
  let(:user) { create(:user) }
  let(:year) { 2021 }
  let(:month) { 1 }
  let(:timespan) { DateTime.new(year, month).beginning_of_month..DateTime.new(year, month).end_of_month }
  let(:monthly_points) { user.points.without_raw_data.where(timestamp: timespan).order(timestamp: :asc) }

  describe '#call' do
    context 'with timezone boundary' do
      # Two points at 23:00 and 23:30 UTC on Jan 1
      # UTC: both day 1
      # Berlin (+1): 00:00 and 00:30 → both day 2
      # New York (-5): 18:00 and 18:30 → both day 1
      let!(:point1) do
        create(:point, user: user, lonlat: 'POINT(13.4 52.5)',
               timestamp: DateTime.new(2021, 1, 1, 23, 0, 0).to_i)
      end
      let!(:point2) do
        create(:point, user: user, lonlat: 'POINT(13.5 52.6)',
               timestamp: DateTime.new(2021, 1, 1, 23, 30, 0).to_i)
      end

      context 'in Etc/UTC' do
        subject { described_class.new(monthly_points, timespan, 'Etc/UTC').call }

        it 'assigns both points to day 1' do
          day1_distance = subject.find { |day, _| day == 1 }&.last
          expect(day1_distance).to be > 0
        end

        it 'assigns zero distance to day 2' do
          day2_distance = subject.find { |day, _| day == 2 }&.last
          expect(day2_distance).to eq(0)
        end
      end

      context 'in Europe/Berlin (+1)' do
        subject { described_class.new(monthly_points, timespan, 'Europe/Berlin').call }

        it 'assigns zero distance to day 1 (both points shift to day 2)' do
          day1_distance = subject.find { |day, _| day == 1 }&.last
          expect(day1_distance).to eq(0)
        end

        it 'assigns both points to day 2 (00:00 and 00:30 CET)' do
          day2_distance = subject.find { |day, _| day == 2 }&.last
          expect(day2_distance).to be > 0
        end
      end

      context 'in America/New_York (-5)' do
        subject { described_class.new(monthly_points, timespan, 'America/New_York').call }

        it 'assigns both points to day 1 (18:00 and 18:30 EST)' do
          day1_distance = subject.find { |day, _| day == 1 }&.last
          expect(day1_distance).to be > 0
        end

        it 'assigns zero distance to day 2' do
          day2_distance = subject.find { |day, _| day == 2 }&.last
          expect(day2_distance).to eq(0)
        end
      end
    end

    context 'with no points' do
      subject { described_class.new(monthly_points, timespan, 'Etc/UTC').call }

      it 'returns 31 zero-distance days for January' do
        expected = (1..31).map { |day| [day, 0] }
        expect(subject).to eq(expected)
      end
    end
  end

  describe '#validate_timezone' do
    subject { described_class.new(monthly_points, timespan, timezone).send(:timezone) }

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

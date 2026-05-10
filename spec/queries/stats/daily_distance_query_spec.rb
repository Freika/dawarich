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

    context 'with points from different imports on the same day' do
      # Morning activity in Vienna and afternoon activity in Salzburg imported
      # as two separate GPX files. The cross-import jump must NOT be counted.
      let(:import_a) { create(:import, user: user) }
      let(:import_b) { create(:import, user: user) }

      let!(:point1) do
        create(:point, user: user, import: import_a, lonlat: 'POINT(16.37 48.21)',
               timestamp: DateTime.new(2021, 1, 1, 6, 0, 0).to_i)
      end
      let!(:point2) do
        create(:point, user: user, import: import_a, lonlat: 'POINT(16.38 48.22)',
               timestamp: DateTime.new(2021, 1, 1, 6, 1, 0).to_i)
      end
      let!(:point3) do
        create(:point, user: user, import: import_b, lonlat: 'POINT(13.04 47.80)',
               timestamp: DateTime.new(2021, 1, 1, 14, 0, 0).to_i)
      end
      let!(:point4) do
        create(:point, user: user, import: import_b, lonlat: 'POINT(13.05 47.81)',
               timestamp: DateTime.new(2021, 1, 1, 14, 1, 0).to_i)
      end

      subject { described_class.new(monthly_points, timespan, 'Etc/UTC').call }

      it 'counts only within-import distances, not the cross-import jump' do
        day1_distance = subject.find { |day, _| day == 1 }&.last
        # Each import contributes ~1.5km locally; the cross-city jump
        # (~260km) must be excluded.
        expect(day1_distance).to be < 10_000
      end
    end

    context 'with real-time tracking points that have a large time gap' do
      # Morning activity in Vienna and afternoon activity in Salzburg tracked
      # continuously without import_id (OwnTracks / Overland style). The gap
      # between the two activities must NOT be counted as distance.
      let!(:point1) do
        create(:point, user: user, lonlat: 'POINT(16.37 48.21)',
               timestamp: DateTime.new(2021, 1, 1, 6, 0, 0).to_i)
      end
      let!(:point2) do
        create(:point, user: user, lonlat: 'POINT(16.38 48.22)',
               timestamp: DateTime.new(2021, 1, 1, 6, 1, 0).to_i)
      end
      let!(:point3) do
        create(:point, user: user, lonlat: 'POINT(13.04 47.80)',
               timestamp: DateTime.new(2021, 1, 1, 14, 0, 0).to_i)
      end
      let!(:point4) do
        create(:point, user: user, lonlat: 'POINT(13.05 47.81)',
               timestamp: DateTime.new(2021, 1, 1, 14, 1, 0).to_i)
      end

      subject { described_class.new(monthly_points, timespan, 'Etc/UTC', minutes_between_routes: 30).call }

      it 'counts only within-segment distances, not the gap between segments' do
        day1_distance = subject.find { |day, _| day == 1 }&.last
        # Each segment contributes ~1.5km; the cross-city jump (~260km)
        # must be excluded.
        expect(day1_distance).to be < 10_000
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

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
        subject { described_class.new(monthly_points, timespan, 'Etc/UTC', minutes_between_routes: 60).call }

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
        subject { described_class.new(monthly_points, timespan, 'Europe/Berlin', minutes_between_routes: 60).call }

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
        subject { described_class.new(monthly_points, timespan, 'America/New_York', minutes_between_routes: 60).call }

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

    context 'with a leg no aircraft could have flown' do
      let!(:heathrow) do
        create(:point, user: user, lonlat: 'POINT(-0.4803 51.4693)',
                       timestamp: DateTime.new(2021, 1, 5, 12, 0, 0).to_i)
      end
      let!(:lax) do
        create(:point, user: user, lonlat: 'POINT(-118.4103 33.9429)',
                       timestamp: DateTime.new(2021, 1, 5, 12, 0, 15).to_i)
      end

      subject { described_class.new(monthly_points, timespan, 'Etc/UTC').call }

      it 'excludes the impossible leg from the day' do
        expect(subject.find { |day, _| day == 5 }.last).to eq(0)
      end
    end

    context 'with a genuine long-haul flight' do
      let!(:lax) do
        create(:point, user: user, lonlat: 'POINT(-118.4103 33.9429)',
                       timestamp: DateTime.new(2021, 1, 6, 0, 30, 0).to_i)
      end
      let!(:heathrow) do
        create(:point, user: user, lonlat: 'POINT(-0.4803 51.4693)',
                       timestamp: DateTime.new(2021, 1, 6, 10, 30, 0).to_i)
      end

      subject { described_class.new(monthly_points, timespan, 'Etc/UTC', minutes_between_routes: 1000).call }

      it 'counts the flight' do
        expect(subject.find { |day, _| day == 6 }.last).to be > 8_000_000
      end
    end

    context 'with points from different imports separated by a long gap' do
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

      it 'counts both local activities but excludes the cross-city jump' do
        day1_distance = subject.find { |day, _| day == 1 }&.last
        # ~1.34km per activity; the Vienna->Salzburg jump is ~250km.
        expect(day1_distance).to be_between(2_000, 3_500)
      end
    end

    context 'with points from different imports a few minutes apart' do
      # A single history split across two upload files. The boundary between
      # them is continuous travel and must still be counted.
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
        create(:point, user: user, import: import_b, lonlat: 'POINT(16.39 48.23)',
               timestamp: DateTime.new(2021, 1, 1, 6, 6, 0).to_i)
      end
      let!(:point4) do
        create(:point, user: user, import: import_b, lonlat: 'POINT(16.40 48.24)',
               timestamp: DateTime.new(2021, 1, 1, 6, 7, 0).to_i)
      end

      subject { described_class.new(monthly_points, timespan, 'Etc/UTC').call }

      it 'counts the segment spanning the import boundary' do
        day1_distance = subject.find { |day, _| day == 1 }&.last
        # Three consecutive ~1.34km segments, including the one across imports.
        expect(day1_distance).to be_between(3_500, 4_500)
      end
    end

    context 'with sparse points inside a single import' do
      # Google Timeline exports store one point per visit and only the start
      # and end of each activity, so consecutive points are far apart in time.
      # A single import is one continuous history and must not be split.
      let(:import) { create(:import, user: user) }

      let!(:point1) do
        create(:point, user: user, import: import, lonlat: 'POINT(16.37 48.21)',
               timestamp: DateTime.new(2021, 1, 1, 8, 0, 0).to_i)
      end
      let!(:point2) do
        create(:point, user: user, import: import, lonlat: 'POINT(14.29 48.31)',
               timestamp: DateTime.new(2021, 1, 1, 9, 30, 0).to_i)
      end

      subject { described_class.new(monthly_points, timespan, 'Etc/UTC', minutes_between_routes: 30).call }

      it 'counts the full drive despite the 90 minute gap' do
        day1_distance = subject.find { |day, _| day == 1 }&.last
        # Vienna -> Linz is ~154km.
        expect(day1_distance).to be_between(150_000, 160_000)
      end
    end

    context 'with a live-tracked point followed by an imported point a few minutes apart' do
      let(:import) { create(:import, user: user) }

      let!(:point1) do
        create(:point, user: user, lonlat: 'POINT(16.37 48.21)',
               timestamp: DateTime.new(2021, 1, 1, 6, 0, 0).to_i)
      end
      let!(:point2) do
        create(:point, user: user, import: import, lonlat: 'POINT(16.38 48.22)',
               timestamp: DateTime.new(2021, 1, 1, 6, 5, 0).to_i)
      end

      subject { described_class.new(monthly_points, timespan, 'Etc/UTC', minutes_between_routes: 30).call }

      it 'counts the segment between the live and imported points' do
        day1_distance = subject.find { |day, _| day == 1 }&.last
        expect(day1_distance).to be_between(1_000, 2_000)
      end
    end

    context 'with sparse points inside a single photo-library import' do
      # Photo integrations (Immich, PhotoPrism, Google Photos) sync the whole
      # library as one import, so its points are snapshots, not a continuous
      # track — the gap between photo locations must not be counted.
      let(:import) { create(:import, user: user, source: :immich_api) }

      let!(:point1) do
        create(:point, user: user, import: import, lonlat: 'POINT(16.37 48.21)',
               timestamp: DateTime.new(2021, 1, 1, 6, 0, 0).to_i)
      end
      let!(:point2) do
        create(:point, user: user, import: import, lonlat: 'POINT(16.38 48.22)',
               timestamp: DateTime.new(2021, 1, 1, 6, 1, 0).to_i)
      end
      let!(:point3) do
        create(:point, user: user, import: import, lonlat: 'POINT(13.04 47.80)',
               timestamp: DateTime.new(2021, 1, 1, 14, 0, 0).to_i)
      end
      let!(:point4) do
        create(:point, user: user, import: import, lonlat: 'POINT(13.05 47.81)',
               timestamp: DateTime.new(2021, 1, 1, 14, 1, 0).to_i)
      end

      subject { described_class.new(monthly_points, timespan, 'Etc/UTC', minutes_between_routes: 30).call }

      it 'excludes the jump between photo clusters despite the shared import' do
        day1_distance = subject.find { |day, _| day == 1 }&.last
        expect(day1_distance).to be_between(2_000, 3_500)
      end
    end

    context 'with a negative minutes_between_routes setting' do
      let!(:point1) do
        create(:point, user: user, lonlat: 'POINT(16.37 48.21)',
               timestamp: DateTime.new(2021, 1, 1, 6, 0, 0).to_i)
      end
      let!(:point2) do
        create(:point, user: user, lonlat: 'POINT(16.38 48.22)',
               timestamp: DateTime.new(2021, 1, 1, 6, 20, 0).to_i)
      end

      subject { described_class.new(monthly_points, timespan, 'Etc/UTC', minutes_between_routes: -5).call }

      it 'falls back to the default threshold and counts the segment' do
        day1_distance = subject.find { |day, _| day == 1 }&.last
        expect(day1_distance).to be_between(1_000, 2_000)
      end
    end

    context 'with two points sharing the same timestamp' do
      # Insertion order fixes ids, so the window tiebreak on id makes the
      # visit order point1 -> point2 -> point3 along a straight line.
      let!(:point1) do
        create(:point, user: user, lonlat: 'POINT(16.37 48.21)',
               timestamp: DateTime.new(2021, 1, 1, 6, 0, 0).to_i)
      end
      let!(:point2) do
        create(:point, user: user, lonlat: 'POINT(16.38 48.22)',
               timestamp: DateTime.new(2021, 1, 1, 6, 1, 0).to_i)
      end
      let!(:point3) do
        create(:point, user: user, lonlat: 'POINT(16.39 48.23)',
               timestamp: DateTime.new(2021, 1, 1, 6, 1, 0).to_i)
      end

      subject { described_class.new(monthly_points, timespan, 'Etc/UTC', minutes_between_routes: 30).call }

      it 'orders tied timestamps deterministically and sums both segments' do
        day1_distance = subject.find { |day, _| day == 1 }&.last
        expect(day1_distance).to be_between(2_000, 3_500)
      end
    end

    context 'with a gap exactly equal to the threshold' do
      let!(:point1) do
        create(:point, user: user, lonlat: 'POINT(16.37 48.21)',
               timestamp: DateTime.new(2021, 1, 1, 6, 0, 0).to_i)
      end
      let!(:point2) do
        create(:point, user: user, lonlat: 'POINT(16.38 48.22)',
               timestamp: DateTime.new(2021, 1, 1, 6, 30, 0).to_i)
      end

      subject { described_class.new(monthly_points, timespan, 'Etc/UTC', minutes_between_routes: 30).call }

      it 'still counts the segment (only a strictly larger gap splits)' do
        day1_distance = subject.find { |day, _| day == 1 }&.last
        expect(day1_distance).to be_between(1_000, 2_000)
      end
    end

    context 'with a short gap spanning local midnight' do
      let!(:point1) do
        create(:point, user: user, lonlat: 'POINT(16.37 48.21)',
               timestamp: DateTime.new(2021, 1, 1, 23, 50, 0).to_i)
      end
      let!(:point2) do
        create(:point, user: user, lonlat: 'POINT(16.38 48.22)',
               timestamp: DateTime.new(2021, 1, 2, 0, 10, 0).to_i)
      end

      subject { described_class.new(monthly_points, timespan, 'Etc/UTC', minutes_between_routes: 30).call }

      it 'does not carry the segment across the day partition' do
        expect(subject.find { |day, _| day == 1 }&.last).to eq(0)
        expect(subject.find { |day, _| day == 2 }&.last).to eq(0)
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
        # ~1.34km per segment; the Vienna->Salzburg jump is ~250km.
        expect(day1_distance).to be_between(2_000, 3_500)
      end
    end

    context 'with a blank minutes_between_routes setting' do
      let!(:point1) do
        create(:point, user: user, lonlat: 'POINT(16.37 48.21)',
               timestamp: DateTime.new(2021, 1, 1, 6, 0, 0).to_i)
      end
      let!(:point2) do
        create(:point, user: user, lonlat: 'POINT(16.38 48.22)',
               timestamp: DateTime.new(2021, 1, 1, 6, 5, 0).to_i)
      end

      subject { described_class.new(monthly_points, timespan, 'Etc/UTC', minutes_between_routes: '').call }

      it 'falls back to the default threshold instead of zeroing every segment' do
        day1_distance = subject.find { |day, _| day == 1 }&.last
        expect(day1_distance).to be_between(1_000, 2_000)
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

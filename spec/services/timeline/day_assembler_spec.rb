# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Timeline::DayAssembler do
  let(:user) { create(:user) }
  let(:place) { create(:place, :with_geodata, name: 'Home', city: 'Berlin', country: 'Germany') }
  let(:place2) { create(:place, :with_geodata, name: 'Office', latitude: 52.52, longitude: 13.40) }

  describe '#call' do
    context 'with visits and tracks on the same day' do
      let(:day) { Time.zone.parse('2025-01-15 00:00:00') }

      let!(:visit1) do
        create(:visit,
               user: user,
               place: place,
               name: 'Home',
               started_at: day + 7.hours,
               ended_at: day + 8.hours,
               duration: 3600)
      end

      let!(:track1) do
        create(:track,
               user: user,
               start_at: day + 8.hours,
               end_at: day + 8.hours + 30.minutes,
               distance: 8500,
               duration: 1800,
               dominant_mode: :cycling)
      end

      let!(:visit2) do
        create(:visit,
               user: user,
               place: place2,
               name: 'Office',
               started_at: day + 8.hours + 30.minutes,
               ended_at: day + 17.hours,
               duration: 30_600)
      end

      subject do
        described_class.new(user, start_at: day.iso8601, end_at: (day + 1.day).iso8601).call
      end

      it 'returns one day entry' do
        expect(subject.length).to eq(1)
        expect(subject.first[:date]).to eq('2025-01-15')
      end

      it 'interleaves visits and tracks chronologically' do
        entries = subject.first[:entries]
        expect(entries.length).to eq(3)
        expect(entries[0][:type]).to eq('visit')
        expect(entries[0][:name]).to eq('Home')
        expect(entries[1][:type]).to eq('journey')
        expect(entries[1][:dominant_mode]).to eq('cycling')
        expect(entries[2][:type]).to eq('visit')
        expect(entries[2][:name]).to eq('Office')
      end

      it 'includes visit_id on visit entries' do
        entries = subject.first[:entries]
        visit_entry = entries.find { |e| e[:type] == 'visit' }
        expect(visit_entry[:visit_id]).to eq(visit1.id)
      end

      it 'includes track_id and metrics on journey entries' do
        entries = subject.first[:entries]
        journey = entries.find { |e| e[:type] == 'journey' }
        expect(journey[:track_id]).to eq(track1.id)
        expect(journey[:avg_speed]).to be_a(Float)
        expect(journey[:distance_unit]).to eq('km')
        expect(journey[:speed_unit]).to eq('km/h')
        expect(journey).to have_key(:elevation_gain)
        expect(journey).to have_key(:elevation_loss)
      end

      it 'calculates summary with distance and places' do
        summary = subject.first[:summary]
        expect(summary[:total_distance]).to eq(8.5)
        expect(summary[:distance_unit]).to eq('km')
        expect(summary[:places_visited]).to eq(2)
      end

      it 'calculates time breakdown' do
        summary = subject.first[:summary]
        expect(summary[:time_moving_minutes]).to eq(30)
        expect(summary[:time_stationary_minutes]).to eq(570)
      end

      it 'provides bounding box' do
        bounds = subject.first[:bounds]
        expect(bounds).to have_key(:sw_lat)
        expect(bounds).to have_key(:sw_lng)
        expect(bounds).to have_key(:ne_lat)
        expect(bounds).to have_key(:ne_lng)
      end
    end

    context 'with only visits' do
      let(:day) { Time.zone.parse('2025-01-15 00:00:00') }

      let!(:visit) do
        create(:visit,
               user: user,
               place: place,
               name: 'Home',
               started_at: day + 10.hours,
               ended_at: day + 12.hours,
               duration: 7200)
      end

      subject do
        described_class.new(user, start_at: day.iso8601, end_at: (day + 1.day).iso8601).call
      end

      it 'returns visit-only entries' do
        entries = subject.first[:entries]
        expect(entries.length).to eq(1)
        expect(entries.first[:type]).to eq('visit')
      end

      it 'reports zero moving time' do
        expect(subject.first[:summary][:time_moving_minutes]).to eq(0)
        expect(subject.first[:summary][:total_distance]).to eq(0.0)
      end
    end

    context 'with only tracks' do
      let(:day) { Time.zone.parse('2025-01-15 00:00:00') }

      let!(:track) do
        create(:track,
               user: user,
               start_at: day + 9.hours,
               end_at: day + 10.hours,
               distance: 15_000,
               duration: 3600,
               dominant_mode: :driving)
      end

      subject do
        described_class.new(user, start_at: day.iso8601, end_at: (day + 1.day).iso8601).call
      end

      it 'returns journey-only entries' do
        entries = subject.first[:entries]
        expect(entries.length).to eq(1)
        expect(entries.first[:type]).to eq('journey')
        expect(entries.first[:distance]).to eq(15.0)
      end

      it 'reports zero stationary time' do
        expect(subject.first[:summary][:time_stationary_minutes]).to eq(0)
        expect(subject.first[:summary][:places_visited]).to eq(0)
      end
    end

    context 'with empty date range' do
      subject do
        described_class.new(
          user,
          start_at: 1.year.ago.iso8601,
          end_at: 11.months.ago.iso8601
        ).call
      end

      it 'returns empty array' do
        expect(subject).to eq([])
      end
    end

    context 'with multi-day range' do
      let(:day1) { Time.zone.parse('2025-01-15 00:00:00') }
      let(:day2) { Time.zone.parse('2025-01-16 00:00:00') }

      let!(:visit_day1) do
        create(:visit,
               user: user,
               place: place,
               name: 'Home',
               started_at: day1 + 10.hours,
               ended_at: day1 + 12.hours,
               duration: 7200)
      end

      let!(:visit_day2) do
        create(:visit,
               user: user,
               place: place2,
               name: 'Office',
               started_at: day2 + 9.hours,
               ended_at: day2 + 17.hours,
               duration: 28_800)
      end

      subject do
        described_class.new(
          user,
          start_at: day1.iso8601,
          end_at: (day2 + 1.day).iso8601
        ).call
      end

      it 'returns one entry per day sorted ascending' do
        expect(subject.length).to eq(2)
        expect(subject[0][:date]).to eq('2025-01-15')
        expect(subject[1][:date]).to eq('2025-01-16')
      end
    end

    context 'with visits without places' do
      let(:day) { Time.zone.parse('2025-01-15 00:00:00') }

      let!(:visit) do
        create(:visit,
               user: user,
               place: nil,
               name: 'Unknown',
               started_at: day + 10.hours,
               ended_at: day + 12.hours,
               duration: 7200)
      end

      subject do
        described_class.new(user, start_at: day.iso8601, end_at: (day + 1.day).iso8601).call
      end

      it 'handles visits without places gracefully' do
        entry = subject.first[:entries].first
        expect(entry[:type]).to eq('visit')
        expect(entry[:name]).to eq('Unknown')
        expect(entry[:place]).to be_nil
      end
    end

    context 'with timezone boundary — event near midnight UTC' do
      # A visit that starts at 23:30 UTC is still Jan 15 in UTC,
      # but already Jan 16 in UTC+1 (Europe/Berlin).
      # DayAssembler groups by `visit.started_at.to_date`, which depends
      # on Time.zone, so the grouping must reflect the configured timezone.

      let(:utc_late) { Time.utc(2025, 1, 15, 23, 30, 0) }

      let!(:late_visit) do
        create(:visit,
               user: user,
               place: place,
               name: 'Late Visit',
               started_at: utc_late,
               ended_at: utc_late + 1.hour,
               duration: 3600)
      end

      context 'when Time.zone is UTC' do
        around do |example|
          Time.use_zone('UTC') { example.run }
        end

        subject do
          described_class.new(
            user,
            start_at: '2025-01-15T00:00:00Z',
            end_at: '2025-01-16T23:59:59Z'
          ).call
        end

        it 'groups the visit on January 15' do
          subject.map { |d| d[:date] }
          visit_day = subject.find { |d| d[:entries].any? { |e| e[:name] == 'Late Visit' } }
          expect(visit_day[:date]).to eq('2025-01-15')
        end
      end

      context 'when Time.zone is UTC+1 (Europe/Berlin)' do
        around do |example|
          Time.use_zone('Europe/Berlin') { example.run }
        end

        subject do
          described_class.new(
            user,
            start_at: '2025-01-15T00:00:00+01:00',
            end_at: '2025-01-17T00:00:00+01:00'
          ).call
        end

        it 'groups the visit on January 16 (next day in Berlin)' do
          visit_day = subject.find { |d| d[:entries].any? { |e| e[:name] == 'Late Visit' } }
          expect(visit_day[:date]).to eq('2025-01-16')
        end
      end
    end

    context 'with timezone boundary — track spanning midnight' do
      let(:before_midnight) { Time.utc(2025, 1, 15, 23, 0, 0) }

      let!(:midnight_track) do
        create(:track,
               user: user,
               start_at: before_midnight,
               end_at: before_midnight + 2.hours,
               distance: 5000,
               duration: 7200,
               dominant_mode: :driving)
      end

      context 'when Time.zone is US Eastern (UTC-5)' do
        around do |example|
          Time.use_zone('Eastern Time (US & Canada)') { example.run }
        end

        subject do
          described_class.new(
            user,
            start_at: '2025-01-15T00:00:00-05:00',
            end_at: '2025-01-16T23:59:59-05:00'
          ).call
        end

        it 'groups the track by its start_at date in Eastern time (Jan 15)' do
          track_day = subject.find { |d| d[:entries].any? { |e| e[:type] == 'journey' } }
          # 23:00 UTC = 18:00 Eastern, still Jan 15
          expect(track_day[:date]).to eq('2025-01-15')
        end
      end

      context 'when Time.zone is UTC+9 (Tokyo)' do
        around do |example|
          Time.use_zone('Tokyo') { example.run }
        end

        subject do
          described_class.new(
            user,
            start_at: '2025-01-15T00:00:00+09:00',
            end_at: '2025-01-17T00:00:00+09:00'
          ).call
        end

        it 'groups the track on January 16 (next day in Tokyo)' do
          track_day = subject.find { |d| d[:entries].any? { |e| e[:type] == 'journey' } }
          # 23:00 UTC = 08:00+1 JST = Jan 16
          expect(track_day[:date]).to eq('2025-01-16')
        end
      end
    end

    context 'with distance_unit parameter' do
      let(:day) { Time.zone.parse('2025-01-15 00:00:00') }

      let!(:track) do
        create(:track,
               user: user,
               start_at: day + 9.hours,
               end_at: day + 10.hours,
               distance: 16_093,
               duration: 3600,
               dominant_mode: :driving)
      end

      it 'converts distance to miles when distance_unit is mi' do
        result = described_class.new(
          user,
          start_at: day.iso8601,
          end_at: (day + 1.day).iso8601,
          distance_unit: 'mi'
        ).call

        journey = result.first[:entries].first
        expect(journey[:distance_unit]).to eq('mi')
        expect(journey[:distance]).to eq(10.0) # 16093m ≈ 10.0 mi
        expect(journey[:speed_unit]).to eq('mph')

        summary = result.first[:summary]
        expect(summary[:distance_unit]).to eq('mi')
        expect(summary[:total_distance]).to eq(10.0)
      end

      it 'defaults to km' do
        result = described_class.new(
          user,
          start_at: day.iso8601,
          end_at: (day + 1.day).iso8601
        ).call

        journey = result.first[:entries].first
        expect(journey[:distance_unit]).to eq('km')
        expect(journey[:distance]).to eq(16.1) # 16093m ≈ 16.1 km
        expect(journey[:speed_unit]).to eq('km/h')
      end
    end

    context 'does not leak data between users' do
      let(:other_user) { create(:user) }
      let(:day) { Time.zone.parse('2025-01-15 00:00:00') }

      let!(:own_visit) do
        create(:visit,
               user: user,
               place: place,
               name: 'My Visit',
               started_at: day + 10.hours,
               ended_at: day + 12.hours,
               duration: 7200)
      end

      let!(:other_visit) do
        create(:visit,
               user: other_user,
               place: place,
               name: 'Other Visit',
               started_at: day + 10.hours,
               ended_at: day + 12.hours,
               duration: 7200)
      end

      subject do
        described_class.new(user, start_at: day.iso8601, end_at: (day + 1.day).iso8601).call
      end

      it 'only returns data for the specified user' do
        entries = subject.first[:entries]
        expect(entries.length).to eq(1)
        expect(entries.first[:name]).to eq('My Visit')
      end
    end

    context 'when start_at or end_at is nil' do
      it 'returns empty array when start_at is nil' do
        result = described_class.new(user, start_at: nil, end_at: '2025-01-16T00:00:00Z').call
        expect(result).to eq([])
      end

      it 'returns empty array when end_at is nil' do
        result = described_class.new(user, start_at: '2025-01-15T00:00:00Z', end_at: nil).call
        expect(result).to eq([])
      end

      it 'returns empty array when both are nil' do
        result = described_class.new(user, start_at: nil, end_at: nil).call
        expect(result).to eq([])
      end
    end
  end
end

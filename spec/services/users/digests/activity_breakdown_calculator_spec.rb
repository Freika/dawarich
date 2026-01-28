# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::Digests::ActivityBreakdownCalculator do
  describe '#call' do
    subject(:calculator) { described_class.new(user, year, month) }

    let(:user) { create(:user) }
    let(:year) { 2024 }
    let(:month) { 5 }

    context 'when user has no tracks or segments' do
      it 'returns an empty hash' do
        expect(calculator.call).to eq({})
      end
    end

    context 'when user has track segments' do
      let!(:track) { create(:track, user: user, start_at: Time.zone.local(2024, 5, 15, 10, 0)) }

      before do
        create(:track_segment, track: track, transportation_mode: :walking, duration: 1800)
        create(:track_segment, track: track, transportation_mode: :driving, duration: 3600)
      end

      it 'returns breakdown with duration and percentage' do
        result = calculator.call

        expect(result['walking']['duration']).to eq(1800)
        expect(result['driving']['duration']).to eq(3600)
        expect(result['walking']['percentage']).to eq(33) # 1800 / 5400 * 100
        expect(result['driving']['percentage']).to eq(67) # 3600 / 5400 * 100
      end
    end

    context 'when user has tracks outside the selected time range' do
      let!(:track_in_range) { create(:track, user: user, start_at: Time.zone.local(2024, 5, 15, 10, 0)) }
      let!(:track_out_of_range) { create(:track, user: user, start_at: Time.zone.local(2024, 6, 15, 10, 0)) }

      before do
        create(:track_segment, track: track_in_range, transportation_mode: :walking, duration: 1800)
        create(:track_segment, track: track_out_of_range, transportation_mode: :driving, duration: 3600)
      end

      it 'only includes segments from tracks within the time range' do
        result = calculator.call

        expect(result.keys).to contain_exactly('walking')
        expect(result['walking']['duration']).to eq(1800)
        expect(result['driving']).to be_nil
      end
    end

    describe 'inter-track stationary time calculation' do
      let(:home_lat) { 52.520008 }
      let(:home_lon) { 13.404954 }
      let(:home_lonlat) { "POINT(#{home_lon} #{home_lat})" }

      let(:work_lat) { 52.530000 }
      let(:work_lon) { 13.420000 }
      let(:work_lonlat) { "POINT(#{work_lon} #{work_lat})" }

      context 'when consecutive tracks start and end in the same location' do
        let!(:track1) do
          create(:track, user: user,
            start_at: Time.zone.local(2024, 5, 15, 8, 0),
            end_at: Time.zone.local(2024, 5, 15, 9, 0))
        end
        let!(:track2) do
          create(:track, user: user,
            start_at: Time.zone.local(2024, 5, 15, 18, 0),
            end_at: Time.zone.local(2024, 5, 15, 19, 0))
        end

        before do
          # Create track segments for existing activity
          create(:track_segment, track: track1, transportation_mode: :driving, duration: 3600)
          create(:track_segment, track: track2, transportation_mode: :driving, duration: 3600)

          # Track1 ends at "home"
          create(:point, user: user, track: track1, timestamp: track1.end_at.to_i,
            lonlat: home_lonlat, latitude: home_lat, longitude: home_lon)

          # Track2 starts at "home" (same location, 9 hours later)
          create(:point, user: user, track: track2, timestamp: track2.start_at.to_i,
            lonlat: home_lonlat, latitude: home_lat, longitude: home_lon)
        end

        it 'counts the gap between tracks as stationary time' do
          result = calculator.call

          # Gap is 9 hours = 32400 seconds
          expect(result['stationary']).to be_present
          expect(result['stationary']['duration']).to eq(32_400)
        end

        it 'includes stationary time in total percentage calculation' do
          result = calculator.call

          total_duration = result.values.sum { |v| v['duration'] }
          # 2 driving segments (3600 each) + 9 hours stationary (32400)
          expect(total_duration).to eq(39_600)
        end
      end

      context 'when consecutive tracks start and end in different locations' do
        let!(:track1) do
          create(:track, user: user,
            start_at: Time.zone.local(2024, 5, 15, 8, 0),
            end_at: Time.zone.local(2024, 5, 15, 9, 0))
        end
        let!(:track2) do
          create(:track, user: user,
            start_at: Time.zone.local(2024, 5, 15, 18, 0),
            end_at: Time.zone.local(2024, 5, 15, 19, 0))
        end

        before do
          create(:track_segment, track: track1, transportation_mode: :driving, duration: 3600)
          create(:track_segment, track: track2, transportation_mode: :driving, duration: 3600)

          # Track1 ends at "work"
          create(:point, user: user, track: track1, timestamp: track1.end_at.to_i,
            lonlat: work_lonlat, latitude: work_lat, longitude: work_lon)

          # Track2 starts at "home" (different location - more than 100m away)
          create(:point, user: user, track: track2, timestamp: track2.start_at.to_i,
            lonlat: home_lonlat, latitude: home_lat, longitude: home_lon)
        end

        it 'does not count the gap as stationary time' do
          result = calculator.call

          expect(result['stationary']).to be_nil
          expect(result.keys).to contain_exactly('driving')
        end
      end

      context 'when gap exceeds maximum threshold (24 hours)' do
        let!(:track1) do
          create(:track, user: user,
            start_at: Time.zone.local(2024, 5, 15, 8, 0),
            end_at: Time.zone.local(2024, 5, 15, 9, 0))
        end
        let!(:track2) do
          create(:track, user: user,
            start_at: Time.zone.local(2024, 5, 17, 9, 0), # 48 hours later
            end_at: Time.zone.local(2024, 5, 17, 10, 0))
        end

        before do
          create(:track_segment, track: track1, transportation_mode: :driving, duration: 3600)
          create(:track_segment, track: track2, transportation_mode: :driving, duration: 3600)

          # Both tracks at home
          create(:point, user: user, track: track1, timestamp: track1.end_at.to_i,
            lonlat: home_lonlat, latitude: home_lat, longitude: home_lon)
          create(:point, user: user, track: track2, timestamp: track2.start_at.to_i,
            lonlat: home_lonlat, latitude: home_lat, longitude: home_lon)
        end

        it 'does not count gaps exceeding 24 hours as stationary' do
          result = calculator.call

          expect(result['stationary']).to be_nil
          expect(result.keys).to contain_exactly('driving')
        end
      end

      context 'when tracks have no points' do
        let!(:track1) do
          create(:track, user: user,
            start_at: Time.zone.local(2024, 5, 15, 8, 0),
            end_at: Time.zone.local(2024, 5, 15, 9, 0))
        end
        let!(:track2) do
          create(:track, user: user,
            start_at: Time.zone.local(2024, 5, 15, 18, 0),
            end_at: Time.zone.local(2024, 5, 15, 19, 0))
        end

        before do
          create(:track_segment, track: track1, transportation_mode: :driving, duration: 3600)
          create(:track_segment, track: track2, transportation_mode: :driving, duration: 3600)
          # No points created
        end

        it 'gracefully handles missing points' do
          result = calculator.call

          expect(result['stationary']).to be_nil
          expect(result.keys).to contain_exactly('driving')
        end
      end

      context 'with multiple consecutive tracks' do
        let!(:track1) do
          create(:track, user: user,
            start_at: Time.zone.local(2024, 5, 15, 6, 0),
            end_at: Time.zone.local(2024, 5, 15, 7, 0))
        end
        let!(:track2) do
          create(:track, user: user,
            start_at: Time.zone.local(2024, 5, 15, 9, 0),
            end_at: Time.zone.local(2024, 5, 15, 10, 0))
        end
        let!(:track3) do
          create(:track, user: user,
            start_at: Time.zone.local(2024, 5, 15, 18, 0),
            end_at: Time.zone.local(2024, 5, 15, 19, 0))
        end

        before do
          create(:track_segment, track: track1, transportation_mode: :driving, duration: 3600)
          create(:track_segment, track: track2, transportation_mode: :driving, duration: 3600)
          create(:track_segment, track: track3, transportation_mode: :driving, duration: 3600)

          # Track1 ends at home
          create(:point, user: user, track: track1, timestamp: track1.end_at.to_i,
            lonlat: home_lonlat, latitude: home_lat, longitude: home_lon)

          # Track2 starts at work (different location) - 2 hour gap, NOT stationary
          create(:point, user: user, track: track2, timestamp: track2.start_at.to_i,
            lonlat: work_lonlat, latitude: work_lat, longitude: work_lon)

          # Track2 ends at work
          create(:point, user: user, track: track2, timestamp: track2.end_at.to_i,
            lonlat: work_lonlat, latitude: work_lat, longitude: work_lon)

          # Track3 starts at work (same location) - 8 hour gap, IS stationary
          create(:point, user: user, track: track3, timestamp: track3.start_at.to_i,
            lonlat: work_lonlat, latitude: work_lat, longitude: work_lon)
        end

        it 'correctly identifies which gaps are stationary' do
          result = calculator.call

          # Only the 8-hour gap between track2 and track3 (same location) counts
          expect(result['stationary']).to be_present
          expect(result['stationary']['duration']).to eq(28_800) # 8 hours
        end
      end

      context 'when combining segment stationary time with inter-track stationary time' do
        let!(:track1) do
          create(:track, user: user,
            start_at: Time.zone.local(2024, 5, 15, 8, 0),
            end_at: Time.zone.local(2024, 5, 15, 9, 0))
        end
        let!(:track2) do
          create(:track, user: user,
            start_at: Time.zone.local(2024, 5, 15, 12, 0),
            end_at: Time.zone.local(2024, 5, 15, 13, 0))
        end

        before do
          # Track1 has a stationary segment (e.g., stopped at traffic)
          create(:track_segment, :stationary, track: track1, duration: 300) # 5 minutes
          create(:track_segment, track: track1, transportation_mode: :driving, duration: 3300)

          create(:track_segment, track: track2, transportation_mode: :driving, duration: 3600)

          # Both tracks at home
          create(:point, user: user, track: track1, timestamp: track1.end_at.to_i,
            lonlat: home_lonlat, latitude: home_lat, longitude: home_lon)
          create(:point, user: user, track: track2, timestamp: track2.start_at.to_i,
            lonlat: home_lonlat, latitude: home_lat, longitude: home_lon)
        end

        it 'combines segment stationary time with inter-track stationary time' do
          result = calculator.call

          # 300 seconds from segment + 3 hours (10800 seconds) from gap = 11100
          expect(result['stationary']['duration']).to eq(11_100)
        end
      end
    end

    describe 'yearly calculation (without month)' do
      subject(:calculator) { described_class.new(user, year, nil) }

      let!(:january_track) { create(:track, user: user, start_at: Time.zone.local(2024, 1, 15, 10, 0)) }
      let!(:december_track) { create(:track, user: user, start_at: Time.zone.local(2024, 12, 15, 10, 0)) }

      before do
        create(:track_segment, track: january_track, transportation_mode: :walking, duration: 1800)
        create(:track_segment, track: december_track, transportation_mode: :cycling, duration: 3600)
      end

      it 'includes tracks from the entire year' do
        result = calculator.call

        expect(result.keys).to contain_exactly('walking', 'cycling')
        expect(result['walking']['duration']).to eq(1800)
        expect(result['cycling']['duration']).to eq(3600)
      end
    end
  end
end

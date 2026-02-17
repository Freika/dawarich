# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Stat, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to validate_presence_of(:year) }
    it { is_expected.to validate_presence_of(:month) }
  end

  describe 'methods' do
    let(:year) { 2021 }
    let(:user) { create(:user) }

    describe '#distance_by_day' do
      subject { stat.distance_by_day }

      let(:user) { create(:user) }
      let(:stat) { create(:stat, year:, month: 1, user:) }
      let(:expected_distance) do
        # 31 day of January
        (1..31).map { |day| [day, 0] }
      end

      context 'when there are points' do
        let!(:points) do
          create(:point, user:, lonlat: 'POINT(1 1)', timestamp: DateTime.new(year, 1, 1, 1))
          create(:point, user:, lonlat: 'POINT(2 2)', timestamp: DateTime.new(year, 1, 1, 2))
        end

        before { expected_distance[0][1] = 156_876 }

        it 'returns distance by day' do
          expect(subject).to eq(expected_distance)
        end
      end

      context 'when there are no points' do
        it 'returns distance by day' do
          expect(subject).to eq(expected_distance)
        end
      end
    end

    describe '#timespan' do
      subject { stat.send(:timespan) }

      let(:stat) { build(:stat, year:, month: 1) }
      let(:expected_timespan) { DateTime.new(year, 1).beginning_of_month..DateTime.new(year, 1).end_of_month }

      it 'returns timespan' do
        expect(subject).to eq(expected_timespan)
      end
    end

    describe '#self.year_distance' do
      subject { described_class.year_distance(year, user) }

      let(:user) { create(:user) }
      let(:expected_distance) do
        (1..12).map { |month| [Date::MONTHNAMES[month], 0] }
      end

      context 'when there are stats' do
        let!(:stats) do
          create(:stat, year:, month: 1, distance: 100, user:)
          create(:stat, year:, month: 2, distance: 200, user:)
        end

        before do
          expected_distance[0][1] = 100
          expected_distance[1][1] = 200
        end

        it 'returns year distance' do
          expect(subject).to eq(expected_distance)
        end
      end

      context 'when there are no stats' do
        it 'returns year distance' do
          expect(subject).to eq(expected_distance)
        end
      end
    end

    describe '#points' do
      subject { stat.points.to_a }

      let(:stat) { create(:stat, year:, month: 1, user:) }
      let(:base_timestamp) { DateTime.new(year, 1, 1, 5, 0, 0) }
      let!(:points) do
        [
          create(:point, user:, timestamp: base_timestamp),
          create(:point, user:, timestamp: base_timestamp + 1.hour),
          create(:point, user:, timestamp: base_timestamp + 2.hours)
        ]
      end

      it 'returns points' do
        expect(subject).to eq(points)
      end
    end

    describe '#calculate_data_bounds' do
      let(:stat) { create(:stat, year: 2024, month: 6, user:) }
      let(:user) { create(:user) }

      context 'when stat has points' do
        before do
          # Create test points within the month (June 2024)
          create(:point,
                 user:,
                 latitude: 40.6,
                 longitude: -74.1,
                 timestamp: Time.new(2024, 6, 1, 12, 0).to_i)
          create(:point,
                 user:,
                 latitude: 40.8,
                 longitude: -73.9,
                 timestamp: Time.new(2024, 6, 15, 15, 0).to_i)
          create(:point,
                 user:,
                 latitude: 40.7,
                 longitude: -74.0,
                 timestamp: Time.new(2024, 6, 30, 18, 0).to_i)

          # Points outside the month (should be ignored)
          create(:point,
                 user:,
                 latitude: 41.0,
                 longitude: -75.0,
                 timestamp: Time.new(2024, 5, 31, 23, 59).to_i) # May
          create(:point,
                 user:,
                 latitude: 39.0,
                 longitude: -72.0,
                 timestamp: Time.new(2024, 7, 1, 0, 1).to_i) # July
        end

        it 'returns correct bounding box for points within the month' do
          result = stat.calculate_data_bounds

          expect(result).to be_a(Hash)
          expect(result[:min_lat]).to eq(40.6)
          expect(result[:max_lat]).to eq(40.8)
          expect(result[:min_lng]).to eq(-74.1)
          expect(result[:max_lng]).to eq(-73.9)
          expect(result[:point_count]).to eq(3)
        end

        context 'with points from different users' do
          let(:other_user) { create(:user) }

          before do
            # Add points from a different user (should be ignored)
            create(:point,
                   user: other_user,
                   latitude: 50.0,
                   longitude: -80.0,
                   timestamp: Time.new(2024, 6, 15, 12, 0).to_i)
          end

          it 'only includes points from the stat user' do
            result = stat.calculate_data_bounds

            expect(result[:min_lat]).to eq(40.6)
            expect(result[:max_lat]).to eq(40.8)
            expect(result[:min_lng]).to eq(-74.1)
            expect(result[:max_lng]).to eq(-73.9)
            expect(result[:point_count]).to eq(3) # Still only 3 points from the stat user
          end
        end

        context 'with single point' do
          let(:single_point_user) { create(:user) }
          let(:single_point_stat) { create(:stat, year: 2024, month: 7, user: single_point_user) }

          before do
            create(:point,
                   user: single_point_user,
                   latitude: 45.5,
                   longitude: -122.65,
                   timestamp: Time.new(2024, 7, 15, 14, 30).to_i)
          end

          it 'returns bounds with same min and max values' do
            result = single_point_stat.calculate_data_bounds

            expect(result[:min_lat]).to eq(45.5)
            expect(result[:max_lat]).to eq(45.5)
            expect(result[:min_lng]).to eq(-122.65)
            expect(result[:max_lng]).to eq(-122.65)
            expect(result[:point_count]).to eq(1)
          end
        end

        context 'with edge case coordinates' do
          let(:edge_user) { create(:user) }
          let(:edge_stat) { create(:stat, year: 2024, month: 8, user: edge_user) }

          before do
            # Test with extreme coordinate values
            create(:point,
                   user: edge_user,
                   latitude: -90.0, # South Pole
                   longitude: -180.0, # Date Line West
                   timestamp: Time.new(2024, 8, 1, 0, 0).to_i)
            create(:point,
                   user: edge_user,
                   latitude: 90.0, # North Pole
                   longitude: 180.0, # Date Line East
                   timestamp: Time.new(2024, 8, 31, 23, 59).to_i)
          end

          it 'handles extreme coordinate values correctly' do
            result = edge_stat.calculate_data_bounds

            expect(result[:min_lat]).to eq(-90.0)
            expect(result[:max_lat]).to eq(90.0)
            expect(result[:min_lng]).to eq(-180.0)
            expect(result[:max_lng]).to eq(180.0)
            expect(result[:point_count]).to eq(2)
          end
        end
      end

      context 'when stat has no points' do
        let(:empty_user) { create(:user) }
        let(:empty_stat) { create(:stat, year: 2024, month: 10, user: empty_user) }

        it 'returns nil' do
          result = empty_stat.calculate_data_bounds

          expect(result).to be_nil
        end
      end

      context 'when stat has points but none within the month timeframe' do
        let(:empty_month_user) { create(:user) }
        let(:empty_month_stat) { create(:stat, year: 2024, month: 9, user: empty_month_user) }

        before do
          # Create points outside the target month
          create(:point,
                 user: empty_month_user,
                 latitude: 40.7,
                 longitude: -74.0,
                 timestamp: Time.new(2024, 8, 31, 23, 59).to_i) # August
          create(:point,
                 user: empty_month_user,
                 latitude: 40.8,
                 longitude: -73.9,
                 timestamp: Time.new(2024, 10, 1, 0, 1).to_i) # October
        end

        it 'returns nil when no points exist in the month' do
          result = empty_month_stat.calculate_data_bounds

          expect(result).to be_nil
        end
      end
    end

    describe '#user_timezone' do
      subject { stat.send(:user_timezone) }

      context 'when user has a timezone set' do
        let(:user) { create(:user, settings: { 'timezone' => 'Europe/Berlin' }) }
        let(:stat) { create(:stat, year: year, month: 1, user: user) }

        it 'returns the user timezone' do
          expect(subject).to eq('Europe/Berlin')
        end
      end

      context 'when user timezone is blank' do
        let(:user) { create(:user, settings: { 'timezone' => '' }) }
        let(:stat) { create(:stat, year: year, month: 1, user: user) }

        it 'falls back to Time.zone.name' do
          expect(subject).to eq(Time.zone.name)
        end
      end

      context 'when user timezone is not set' do
        let(:user) { create(:user, settings: {}) }
        let(:stat) { create(:stat, year: year, month: 1, user: user) }

        it 'returns the default UTC timezone' do
          expect(subject).to eq('UTC')
        end
      end
    end

    describe '#distance_by_day with timezone' do
      let(:stat) { create(:stat, year: year, month: 1, user: user) }

      # Two points at 23:00 and 23:30 UTC on Jan 1
      # UTC: both day 1; Berlin (+1): both day 2
      let!(:point1) do
        create(:point, user: user, lonlat: 'POINT(13.4 52.5)',
               timestamp: DateTime.new(year, 1, 1, 23, 0, 0).to_i)
      end
      let!(:point2) do
        create(:point, user: user, lonlat: 'POINT(13.5 52.6)',
               timestamp: DateTime.new(year, 1, 1, 23, 30, 0).to_i)
      end

      context 'with UTC user' do
        let(:user) { create(:user, settings: { 'timezone' => 'Etc/UTC' }) }

        it 'assigns distance to day 1' do
          result = stat.distance_by_day
          day1_distance = result.find { |day, _| day == 1 }&.last
          expect(day1_distance).to be > 0
        end

        it 'assigns zero distance to day 2' do
          result = stat.distance_by_day
          day2_distance = result.find { |day, _| day == 2 }&.last
          expect(day2_distance).to eq(0)
        end
      end

      context 'with Europe/Berlin user' do
        let(:user) { create(:user, settings: { 'timezone' => 'Europe/Berlin' }) }

        it 'assigns zero distance to day 1 (both points shift to day 2 in Berlin)' do
          result = stat.distance_by_day
          day1_distance = result.find { |day, _| day == 1 }&.last
          expect(day1_distance).to eq(0)
        end

        it 'assigns distance to day 2' do
          result = stat.distance_by_day
          day2_distance = result.find { |day, _| day == 2 }&.last
          expect(day2_distance).to be > 0
        end
      end
    end

    describe 'sharing settings' do
      let(:user) { create(:user) }
      let(:stat) { create(:stat, year: 2024, month: 6, user: user) }

      describe '#sharing_enabled?' do
        context 'when sharing_settings is nil' do
          before { stat.update_column(:sharing_settings, nil) }

          it 'returns false' do
            expect(stat.sharing_enabled?).to be false
          end
        end

        context 'when sharing_settings is empty hash' do
          before { stat.update(sharing_settings: {}) }

          it 'returns false' do
            expect(stat.sharing_enabled?).to be false
          end
        end

        context 'when enabled is false' do
          before { stat.update(sharing_settings: { 'enabled' => false }) }

          it 'returns false' do
            expect(stat.sharing_enabled?).to be false
          end
        end

        context 'when enabled is true' do
          before { stat.update(sharing_settings: { 'enabled' => true }) }

          it 'returns true' do
            expect(stat.sharing_enabled?).to be true
          end
        end

        context 'when enabled is a string "true"' do
          before { stat.update(sharing_settings: { 'enabled' => 'true' }) }

          it 'returns false (strict boolean check)' do
            expect(stat.sharing_enabled?).to be false
          end
        end
      end

      describe '#sharing_expired?' do
        context 'when sharing_settings is nil' do
          before { stat.update_column(:sharing_settings, nil) }

          it 'returns false' do
            expect(stat.sharing_expired?).to be false
          end
        end

        context 'when expiration is blank' do
          before { stat.update(sharing_settings: { 'enabled' => true }) }

          it 'returns false' do
            expect(stat.sharing_expired?).to be false
          end
        end

        context 'when expiration is present but expires_at is blank' do
          before do
            stat.update(sharing_settings: {
              'enabled' => true,
              'expiration' => '1h'
            })
          end

          it 'returns true' do
            expect(stat.sharing_expired?).to be true
          end
        end

        context 'when expires_at is in the future' do
          before do
            stat.update(sharing_settings: {
              'enabled' => true,
              'expiration' => '1h',
              'expires_at' => 1.hour.from_now.iso8601
            })
          end

          it 'returns false' do
            expect(stat.sharing_expired?).to be false
          end
        end

        context 'when expires_at is in the past' do
          before do
            stat.update(sharing_settings: {
              'enabled' => true,
              'expiration' => '1h',
              'expires_at' => 1.hour.ago.iso8601
            })
          end

          it 'returns true' do
            expect(stat.sharing_expired?).to be true
          end
        end

        context 'when expires_at is 1 second in the future' do
          before do
            stat.update(sharing_settings: {
              'enabled' => true,
              'expiration' => '1h',
              'expires_at' => 1.second.from_now.iso8601
            })
          end

          it 'returns false (not yet expired)' do
            expect(stat.sharing_expired?).to be false
          end
        end

        context 'when expires_at is invalid date string' do
          before do
            stat.update(sharing_settings: {
              'enabled' => true,
              'expiration' => '1h',
              'expires_at' => 'invalid-date'
            })
          end

          it 'returns true (treats as expired)' do
            expect(stat.sharing_expired?).to be true
          end
        end

        context 'when expires_at is nil' do
          before do
            stat.update(sharing_settings: {
              'enabled' => true,
              'expiration' => '1h',
              'expires_at' => nil
            })
          end

          it 'returns true' do
            expect(stat.sharing_expired?).to be true
          end
        end

        context 'when expires_at is empty string' do
          before do
            stat.update(sharing_settings: {
              'enabled' => true,
              'expiration' => '1h',
              'expires_at' => ''
            })
          end

          it 'returns true' do
            expect(stat.sharing_expired?).to be true
          end
        end
      end

      describe '#public_accessible?' do
        context 'when sharing_settings is nil' do
          before { stat.update_column(:sharing_settings, nil) }

          it 'returns false' do
            expect(stat.public_accessible?).to be false
          end
        end

        context 'when sharing is not enabled' do
          before { stat.update(sharing_settings: { 'enabled' => false }) }

          it 'returns false' do
            expect(stat.public_accessible?).to be false
          end
        end

        context 'when sharing is enabled but expired' do
          before do
            stat.update(sharing_settings: {
              'enabled' => true,
              'expiration' => '1h',
              'expires_at' => 1.hour.ago.iso8601
            })
          end

          it 'returns false' do
            expect(stat.public_accessible?).to be false
          end
        end

        context 'when sharing is enabled and not expired' do
          before do
            stat.update(sharing_settings: {
              'enabled' => true,
              'expiration' => '1h',
              'expires_at' => 1.hour.from_now.iso8601
            })
          end

          it 'returns true' do
            expect(stat.public_accessible?).to be true
          end
        end

        context 'when sharing is enabled with no expiration' do
          before do
            stat.update(sharing_settings: { 'enabled' => true })
          end

          it 'returns true' do
            expect(stat.public_accessible?).to be true
          end
        end
      end
    end
  end
end

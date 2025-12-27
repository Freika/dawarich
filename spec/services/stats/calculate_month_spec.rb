# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Stats::CalculateMonth do
  describe '#call' do
    subject(:calculate_stats) { described_class.new(user.id, year, month).call }

    let(:user) { create(:user) }
    let(:year) { 2021 }
    let(:month) { 1 }

    context 'when there are no points' do
      it 'does not create stats' do
        expect { calculate_stats }.not_to(change { Stat.count })
      end

      context 'when stats already exist for the month' do
        before do
          create(:stat, user: user, year: year, month: month)
        end

        it 'deletes existing stats for that month' do
          expect { calculate_stats }.to change { Stat.count }.by(-1)
        end
      end
    end

    context 'when there are points' do
      let(:timestamp1) { DateTime.new(year, month, 1, 12).to_i }
      let(:timestamp2) { DateTime.new(year, month, 1, 13).to_i }
      let(:timestamp3) { DateTime.new(year, month, 1, 14).to_i }
      let!(:import) { create(:import, user:) }
      let!(:point1) do
        create(:point,
               user:,
               import:,
               timestamp: timestamp1,
               lonlat: 'POINT(14.452712811406352 52.107902115161316)')
      end
      let!(:point2) do
        create(:point,
               user:,
               import:,
               timestamp: timestamp2,
               lonlat: 'POINT(12.291519487061901 51.9746598171507)')
      end
      let!(:point3) do
        create(:point,
               user:,
               import:,
               timestamp: timestamp3,
               lonlat: 'POINT(9.77973105800526 52.72859111523629)')
      end

      context 'when calculating distance' do
        it 'creates stats' do
          expect { calculate_stats }.to change { Stat.count }.by(1)
        end

        it 'calculates distance in meters consistently' do
          calculate_stats

          # Distance should be calculated in meters regardless of user unit preference
          # The actual distance between the test points is approximately 340 km = 340,000 meters
          expect(user.stats.last.distance).to be_within(1000).of(340_000)
        end

        context 'when there is an error' do
          before do
            allow(Stat).to receive(:find_or_initialize_by).and_raise(StandardError)
          end

          it 'does not create stats' do
            expect { calculate_stats }.not_to(change { Stat.count })
          end

          it 'creates a notification' do
            expect { calculate_stats }.to change { Notification.count }.by(1)
          end
        end
      end

      context 'when user prefers miles' do
        before do
          user.update(settings: { maps: { distance_unit: 'mi' } })
        end

        it 'still stores distance in meters (same as km users)' do
          calculate_stats

          # Distance stored should be the same regardless of user preference (meters)
          expect(user.stats.last.distance).to be_within(1000).of(340_000)
        end
      end

      context 'when calculating visited cities and countries' do
        let(:timestamp_base) { DateTime.new(year, month, 1, 12).to_i }
        let!(:import) { create(:import, user:) }

        context 'when user spent more than MIN_MINUTES_SPENT_IN_CITY in a city' do
          let!(:berlin_points) do
            [
              create(:point, user:, import:, timestamp: timestamp_base,
                     city: 'Berlin', country_name: 'Germany',
                     lonlat: 'POINT(13.404954 52.520008)'),
              create(:point, user:, import:, timestamp: timestamp_base + 30.minutes,
                     city: 'Berlin', country_name: 'Germany',
                     lonlat: 'POINT(13.404954 52.520008)'),
              create(:point, user:, import:, timestamp: timestamp_base + 70.minutes,
                     city: 'Berlin', country_name: 'Germany',
                     lonlat: 'POINT(13.404954 52.520008)')
            ]
          end

          it 'includes the city in toponyms' do
            calculate_stats

            stat = user.stats.last
            expect(stat.toponyms).not_to be_empty
            expect(stat.toponyms.first['country']).to eq('Germany')
            expect(stat.toponyms.first['cities']).not_to be_empty
            expect(stat.toponyms.first['cities'].first['city']).to eq('Berlin')
          end
        end

        context 'when user spent less than MIN_MINUTES_SPENT_IN_CITY in a city' do
          let!(:prague_points) do
            [
              create(:point, user:, import:, timestamp: timestamp_base,
                     city: 'Prague', country_name: 'Czech Republic',
                     lonlat: 'POINT(14.4378 50.0755)'),
              create(:point, user:, import:, timestamp: timestamp_base + 10.minutes,
                     city: 'Prague', country_name: 'Czech Republic',
                     lonlat: 'POINT(14.4378 50.0755)'),
              create(:point, user:, import:, timestamp: timestamp_base + 20.minutes,
                     city: 'Prague', country_name: 'Czech Republic',
                     lonlat: 'POINT(14.4378 50.0755)')
            ]
          end

          it 'excludes the city from toponyms' do
            calculate_stats

            stat = user.stats.last
            expect(stat.toponyms).not_to be_empty

            # Country should be listed but with no cities
            czech_country = stat.toponyms.find { |t| t['country'] == 'Czech Republic' }
            expect(czech_country).not_to be_nil
            expect(czech_country['cities']).to be_empty
          end
        end

        context 'when user visited multiple cities with mixed durations' do
          let!(:mixed_points) do
            [
              # Berlin: 70 minutes (should be included)
              create(:point, user:, import:, timestamp: timestamp_base,
                     city: 'Berlin', country_name: 'Germany',
                     lonlat: 'POINT(13.404954 52.520008)'),
              create(:point, user:, import:, timestamp: timestamp_base + 70.minutes,
                     city: 'Berlin', country_name: 'Germany',
                     lonlat: 'POINT(13.404954 52.520008)'),

              # Prague: 20 minutes (should be excluded)
              create(:point, user:, import:, timestamp: timestamp_base + 100.minutes,
                     city: 'Prague', country_name: 'Czech Republic',
                     lonlat: 'POINT(14.4378 50.0755)'),
              create(:point, user:, import:, timestamp: timestamp_base + 120.minutes,
                     city: 'Prague', country_name: 'Czech Republic',
                     lonlat: 'POINT(14.4378 50.0755)'),

              # Vienna: 90 minutes (should be included)
              create(:point, user:, import:, timestamp: timestamp_base + 150.minutes,
                     city: 'Vienna', country_name: 'Austria',
                     lonlat: 'POINT(16.3738 48.2082)'),
              create(:point, user:, import:, timestamp: timestamp_base + 240.minutes,
                     city: 'Vienna', country_name: 'Austria',
                     lonlat: 'POINT(16.3738 48.2082)')
            ]
          end

          it 'only includes cities where user spent >= MIN_MINUTES_SPENT_IN_CITY' do
            calculate_stats

            stat = user.stats.last
            expect(stat.toponyms).not_to be_empty

            # Get all cities from all countries
            all_cities = stat.toponyms.flat_map { |t| t['cities'].map { |c| c['city'] } }

            # Berlin and Vienna should be included
            expect(all_cities).to include('Berlin', 'Vienna')

            # Prague should NOT be included
            expect(all_cities).not_to include('Prague')

            # Should have exactly 2 cities
            expect(all_cities.size).to eq(2)
          end
        end
      end

      context 'when invalidating caches' do
        it 'invalidates user caches after updating stats' do
          cache_service = instance_double(Cache::InvalidateUserCaches)
          allow(Cache::InvalidateUserCaches).to receive(:new).with(user.id).and_return(cache_service)
          allow(cache_service).to receive(:call)

          calculate_stats

          expect(cache_service).to have_received(:call)
        end

        it 'does not invalidate caches when there are no points' do
          # Create a new user without points
          new_user = create(:user)
          service = described_class.new(new_user.id, year, month)

          expect(Cache::InvalidateUserCaches).not_to receive(:new)

          service.call
        end
      end
    end
  end
end

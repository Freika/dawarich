# frozen_string_literal: true

require 'rails_helper'

RSpec.describe LocationSearch::ResultAggregator do
  let(:service) { described_class.new }

  describe '#group_points_into_visits' do
    context 'with empty points array' do
      it 'returns empty array' do
        result = service.group_points_into_visits([])
        expect(result).to eq([])
      end
    end

    context 'with single point' do
      let(:single_point) do
        {
          id: 1,
          timestamp: 1_711_814_700,
          coordinates: [52.5200, 13.4050],
          distance_meters: 45.5,
          accuracy: 10,
          date: '2024-03-20T18:45:00Z',
          city: 'Berlin',
          country: 'Germany',
          altitude: 100
        }
      end

      it 'creates a single visit' do
        result = service.group_points_into_visits([single_point])

        expect(result.length).to eq(1)
        visit = result.first
        expect(visit[:timestamp]).to eq(1_711_814_700)
        expect(visit[:coordinates]).to eq([52.5200, 13.4050])
        expect(visit[:points_count]).to eq(1)
      end

      it 'estimates duration for single point visits' do
        result = service.group_points_into_visits([single_point])

        visit = result.first
        expect(visit[:duration_estimate]).to eq('~15 minutes')
        expect(visit[:visit_details][:duration_minutes]).to eq(15)
      end
    end

    context 'with consecutive points' do
      let(:consecutive_points) do
        [
          {
            id: 1,
            timestamp: 1_711_814_700, # 18:45
            coordinates: [52.5200, 13.4050],
            distance_meters: 45.5,
            accuracy: 10,
            date: '2024-03-20T18:45:00Z',
            city: 'Berlin',
            country: 'Germany'
          },
          {
            id: 2,
            timestamp: 1_711_816_500, # 19:15 (30 minutes later)
            coordinates: [52.5201, 13.4051],
            distance_meters: 48.2,
            accuracy: 8,
            date: '2024-03-20T19:15:00Z',
            city: 'Berlin',
            country: 'Germany'
          },
          {
            id: 3,
            timestamp: 1_711_817_400, # 19:30 (15 minutes later)
            coordinates: [52.5199, 13.4049],
            distance_meters: 42.1,
            accuracy: 12,
            date: '2024-03-20T19:30:00Z',
            city: 'Berlin',
            country: 'Germany'
          }
        ]
      end

      it 'groups consecutive points into single visit' do
        result = service.group_points_into_visits(consecutive_points)

        expect(result.length).to eq(1)
        visit = result.first
        expect(visit[:points_count]).to eq(3)
      end

      it 'calculates visit duration from start to end' do
        result = service.group_points_into_visits(consecutive_points)

        visit = result.first
        expect(visit[:duration_estimate]).to eq('~45 minutes')
        expect(visit[:visit_details][:duration_minutes]).to eq(45)
      end

      it 'uses most accurate point coordinates' do
        result = service.group_points_into_visits(consecutive_points)

        visit = result.first
        # Point with accuracy 8 should be selected
        expect(visit[:coordinates]).to eq([52.5201, 13.4051])
        expect(visit[:accuracy_meters]).to eq(8)
      end

      it 'calculates average distance' do
        result = service.group_points_into_visits(consecutive_points)

        visit = result.first
        expected_avg = (45.5 + 48.2 + 42.1) / 3
        expect(visit[:distance_meters]).to eq(expected_avg.round(2))
      end

      it 'sets correct start and end times' do
        result = service.group_points_into_visits(consecutive_points)

        visit = result.first
        expect(visit[:visit_details][:start_time]).to eq('2024-03-20T18:45:00Z')
        expect(visit[:visit_details][:end_time]).to eq('2024-03-20T19:30:00Z')
      end
    end

    context 'with separate visits (time gaps)' do
      let(:separate_visits_points) do
        [
          {
            id: 1,
            timestamp: 1_711_814_700, # 18:45
            coordinates: [52.5200, 13.4050],
            distance_meters: 45.5,
            accuracy: 10,
            date: '2024-03-20T18:45:00Z',
            city: 'Berlin',
            country: 'Germany'
          },
          {
            id: 2,
            timestamp: 1_711_816_500, # 19:15 (30 minutes later - within threshold)
            coordinates: [52.5201, 13.4051],
            distance_meters: 48.2,
            accuracy: 8,
            date: '2024-03-20T19:15:00Z',
            city: 'Berlin',
            country: 'Germany'
          },
          {
            id: 3,
            timestamp: 1_711_820_100, # 20:15 (60 minutes after last point - exceeds threshold)
            coordinates: [52.5199, 13.4049],
            distance_meters: 42.1,
            accuracy: 12,
            date: '2024-03-20T20:15:00Z',
            city: 'Berlin',
            country: 'Germany'
          }
        ]
      end

      it 'creates separate visits when time gap exceeds threshold' do
        result = service.group_points_into_visits(separate_visits_points)

        expect(result.length).to eq(2)
        expect(result.first[:points_count]).to eq(1) # Most recent visit (20:15)
        expect(result.last[:points_count]).to eq(2)  # Earlier visit (18:45-19:15)
      end

      it 'orders visits by timestamp descending (most recent first)' do
        result = service.group_points_into_visits(separate_visits_points)

        expect(result.first[:timestamp]).to be > result.last[:timestamp]
      end
    end

    context 'with duration formatting' do
      let(:points_with_various_durations) do
        # Helper to create points with time differences
        base_time = 1_711_814_700

        [
          # Short visit (25 minutes) - 2 points 25 minutes apart
          { id: 1, timestamp: base_time, accuracy: 10, coordinates: [52.5200, 13.4050], distance_meters: 50,
date: '2024-03-20T18:45:00Z' },
          { id: 2, timestamp: base_time + 25 * 60, accuracy: 10, coordinates: [52.5200, 13.4050], distance_meters: 50,
date: '2024-03-20T19:10:00Z' },

          # Long visit (2 hours 15 minutes) - points every 15 minutes to stay within 30min threshold
          { id: 3, timestamp: base_time + 70 * 60, accuracy: 10, coordinates: [52.5300, 13.4100], distance_meters: 30,
date: '2024-03-20T19:55:00Z' },
          { id: 4, timestamp: base_time + 85 * 60, accuracy: 10, coordinates: [52.5300, 13.4100], distance_meters: 30,
date: '2024-03-20T20:10:00Z' },
          { id: 5, timestamp: base_time + 100 * 60, accuracy: 10, coordinates: [52.5300, 13.4100], distance_meters: 30,
date: '2024-03-20T20:25:00Z' },
          { id: 6, timestamp: base_time + 115 * 60, accuracy: 10, coordinates: [52.5300, 13.4100], distance_meters: 30,
date: '2024-03-20T20:40:00Z' },
          { id: 7, timestamp: base_time + 130 * 60, accuracy: 10, coordinates: [52.5300, 13.4100], distance_meters: 30,
date: '2024-03-20T20:55:00Z' },
          { id: 8, timestamp: base_time + 145 * 60, accuracy: 10, coordinates: [52.5300, 13.4100], distance_meters: 30,
date: '2024-03-20T21:10:00Z' },
          { id: 9, timestamp: base_time + 160 * 60, accuracy: 10, coordinates: [52.5300, 13.4100], distance_meters: 30,
date: '2024-03-20T21:25:00Z' },
          { id: 10, timestamp: base_time + 175 * 60, accuracy: 10, coordinates: [52.5300, 13.4100],
distance_meters: 30, date: '2024-03-20T21:40:00Z' },
          { id: 11, timestamp: base_time + 190 * 60, accuracy: 10, coordinates: [52.5300, 13.4100],
distance_meters: 30, date: '2024-03-20T21:55:00Z' },
          { id: 12, timestamp: base_time + 205 * 60, accuracy: 10, coordinates: [52.5300, 13.4100],
distance_meters: 30, date: '2024-03-20T22:10:00Z' }
        ]
      end

      it 'formats duration correctly for minutes only' do
        short_visit_points = points_with_various_durations.take(2)
        result = service.group_points_into_visits(short_visit_points)

        expect(result.first[:duration_estimate]).to eq('~25 minutes')
      end

      it 'formats duration correctly for hours and minutes' do
        long_visit_points = points_with_various_durations.drop(2)
        result = service.group_points_into_visits(long_visit_points)

        expect(result.first[:duration_estimate]).to eq('~2 hours 15 minutes')
      end

      it 'formats duration correctly for hours only' do
        # Create points within threshold but exactly 2 hours apart from first to last
        exact_hour_points = [
          { id: 1, timestamp: 1_711_814_700, accuracy: 10, coordinates: [52.5200, 13.4050],
            distance_meters: 50, date: '2024-03-20T18:45:00Z' },
          { id: 2, timestamp: 1_711_814_700 + 25 * 60, accuracy: 10, coordinates: [52.5200, 13.4050],
            distance_meters: 50, date: '2024-03-20T19:10:00Z' },
          { id: 3, timestamp: 1_711_814_700 + 50 * 60, accuracy: 10, coordinates: [52.5200, 13.4050],
            distance_meters: 50, date: '2024-03-20T19:35:00Z' },
          { id: 4, timestamp: 1_711_814_700 + 75 * 60, accuracy: 10, coordinates: [52.5200, 13.4050],
            distance_meters: 50, date: '2024-03-20T20:00:00Z' },
          { id: 5, timestamp: 1_711_814_700 + 100 * 60, accuracy: 10, coordinates: [52.5200, 13.4050],
distance_meters: 50, date: '2024-03-20T20:25:00Z' },
          { id: 6, timestamp: 1_711_814_700 + 120 * 60, accuracy: 10, coordinates: [52.5200, 13.4050],
distance_meters: 50, date: '2024-03-20T20:45:00Z' }
        ]

        result = service.group_points_into_visits(exact_hour_points)

        expect(result.first[:duration_estimate]).to eq('~2 hours')
      end
    end

    context 'with altitude data' do
      let(:points_with_altitude) do
        [
          {
            id: 1, timestamp: 1_711_814_700, coordinates: [52.5200, 13.4050],
            accuracy: 10, distance_meters: 50, altitude: 100,
            date: '2024-03-20T18:45:00Z'
          },
          {
            id: 2, timestamp: 1_711_815_600, coordinates: [52.5201, 13.4051],
            accuracy: 10, distance_meters: 50, altitude: 105,
            date: '2024-03-20T19:00:00Z'
          },
          {
            id: 3, timestamp: 1_711_816_500, coordinates: [52.5199, 13.4049],
            accuracy: 10, distance_meters: 50, altitude: 95,
            date: '2024-03-20T19:15:00Z'
          }
        ]
      end

      it 'includes altitude range in visit details' do
        result = service.group_points_into_visits(points_with_altitude)

        visit = result.first
        expect(visit[:visit_details][:altitude_range]).to eq('95m - 105m')
      end

      context 'with same altitude for all points' do
        before do
          points_with_altitude.each { |p| p[:altitude] = 100 }
        end

        it 'shows single altitude value' do
          result = service.group_points_into_visits(points_with_altitude)

          visit = result.first
          expect(visit[:visit_details][:altitude_range]).to eq('100m')
        end
      end

      context 'with missing altitude data' do
        before do
          points_with_altitude.each { |p| p.delete(:altitude) }
        end

        it 'handles missing altitude gracefully' do
          result = service.group_points_into_visits(points_with_altitude)

          visit = result.first
          expect(visit[:visit_details][:altitude_range]).to be_nil
        end
      end
    end

    context 'with unordered points' do
      let(:unordered_points) do
        [
          { id: 3, timestamp: 1_711_817_400, coordinates: [52.5199, 13.4049], accuracy: 10, distance_meters: 50,
date: '2024-03-20T19:30:00Z' },
          { id: 1, timestamp: 1_711_814_700, coordinates: [52.5200, 13.4050], accuracy: 10, distance_meters: 50,
date: '2024-03-20T18:45:00Z' },
          { id: 2, timestamp: 1_711_816_500, coordinates: [52.5201, 13.4051], accuracy: 10, distance_meters: 50,
date: '2024-03-20T19:15:00Z' }
        ]
      end

      it 'handles unordered input correctly' do
        result = service.group_points_into_visits(unordered_points)

        visit = result.first
        expect(visit[:visit_details][:start_time]).to eq('2024-03-20T18:45:00Z')
        expect(visit[:visit_details][:end_time]).to eq('2024-03-20T19:30:00Z')
      end
    end
  end
end

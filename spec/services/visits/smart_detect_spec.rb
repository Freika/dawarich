# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Visits::SmartDetect do
  let(:user) { create(:user) }
  let(:start_at) { 1.day.ago }
  let(:end_at) { Time.current }

  subject(:detector) { described_class.new(user, start_at:, end_at:) }

  describe '#call' do
    context 'when there are no points' do
      it 'returns an empty array' do
        expect(detector.call).to eq([])
      end
    end

    context 'with a simple visit' do
      let!(:points) do
        [
          create(:point, user:, lonlat: 'POINT(0 0)', timestamp: 1.hour.ago),
          create(:point, user:, lonlat: 'POINT(0.00001 0.00001)', timestamp: 50.minutes.ago),
          create(:point, user:, lonlat: 'POINT(0.00002 0.00002)', timestamp: 40.minutes.ago)
        ]
      end

      it 'creates a visit' do
        expect { detector.call }.to change(Visit, :count).by(1)
      end

      it 'assigns points to the visit' do
        visits = detector.call
        expect(visits.first.points).to match_array(points)
      end

      it 'sets correct visit attributes' do
        visit = detector.call.first
        expect(visit).to have_attributes(
          started_at: be_within(1.second).of(1.hour.ago),
          ended_at: be_within(1.second).of(40.minutes.ago),
          duration: be_within(1).of(20), # 20 minutes
          status: 'suggested'
        )
      end
    end

    context 'with points containing geodata' do
      let(:geodata) do
        {
          'features' => [
            {
              'properties' => {
                'type' => 'shop',
                'name' => 'Coffee Shop',
                'street' => 'Main Street',
                'city' => 'Example City',
                'state' => 'Example State'
              }
            }
          ]
        }
      end

      let!(:points) do
        [
          create(:point, user:, lonlat: 'POINT(0 0)', timestamp: 1.hour.ago,
                geodata: geodata),
          create(:point, user:, lonlat: 'POINT(0.00001 0.00001)', timestamp: 50.minutes.ago,
                geodata: geodata),
          create(:point, user:, lonlat: 'POINT(0.00002 0.00002)', timestamp: 40.minutes.ago,
                geodata: geodata)
        ]
      end

      it 'suggests a name based on geodata' do
        visit = detector.call.first
        expect(visit.name).to eq('Coffee Shop, Main Street, Example City, Example State')
      end

      context 'with mixed feature types' do
        let(:mixed_geodata1) do
          {
            'features' => [
              {
                'properties' => {
                  'type' => 'shop',
                  'name' => 'Coffee Shop',
                  'street' => 'Main Street'
                }
              }
            ]
          }
        end

        let(:mixed_geodata2) do
          {
            'features' => [
              {
                'properties' => {
                  'type' => 'restaurant',
                  'name' => 'Burger Place',
                  'street' => 'Main Street'
                }
              }
            ]
          }
        end

        let!(:points) do
          [
            create(:point, user:, lonlat: 'POINT(0 0)', timestamp: 1.hour.ago,
                  geodata: mixed_geodata1),
            create(:point, user:, lonlat: 'POINT(0.00001 0.00001)', timestamp: 50.minutes.ago,
                  geodata: mixed_geodata1),
            create(:point, user:, lonlat: 'POINT(0.00002 0.00002)', timestamp: 40.minutes.ago,
                  geodata: mixed_geodata2)
          ]
        end

        it 'uses the most common feature type and name' do
          visit = detector.call.first
          expect(visit.name).to eq('Coffee Shop, Main Street')
        end
      end

      context 'with empty or invalid geodata' do
        let!(:points) do
          [
            create(:point, user:, lonlat: 'POINT(0 0)', timestamp: 1.hour.ago,
                  geodata: {}),
            create(:point, user:, lonlat: 'POINT(0.00001 0.00001)', timestamp: 50.minutes.ago,
                  geodata: nil),
            create(:point, user:, lonlat: 'POINT(0.00002 0.00002)', timestamp: 40.minutes.ago,
                  geodata: { 'features' => [] })
          ]
        end

        it 'falls back to Unknown Location' do
          visit = detector.call.first
          expect(visit.name).to eq('Unknown Location')
        end
      end
    end

    context 'with multiple visits to the same place' do
      let!(:morning_points) do
        [
          create(:point, user:, lonlat: 'POINT(0 0)', timestamp: 8.hours.ago),
          create(:point, user:, lonlat: 'POINT(0.00001 0.00001)', timestamp: 7.hours.ago),
          create(:point, user:, lonlat: 'POINT(0.00002 0.00002)', timestamp: 6.hours.ago)
        ]
      end

      let!(:afternoon_points) do
        [
          create(:point, user:, lonlat: 'POINT(0 0)', timestamp: 3.hours.ago),
          create(:point, user:, lonlat: 'POINT(0.00001 0.00001)', timestamp: 2.hours.ago),
          create(:point, user:, lonlat: 'POINT(0.00002 0.00002)', timestamp: 1.hour.ago)
        ]
      end

      it 'creates two visits' do
        expect { detector.call }.to change(Visit, :count).by(2)
      end

      it 'assigns correct points to each visit' do
        visits = detector.call
        expect(visits.first.points).to match_array(morning_points)
        expect(visits.last.points).to match_array(afternoon_points)
      end
    end

    context 'with a known area' do
      let!(:area) { create(:area, user:, latitude: 0, longitude: 0, radius: 100, name: 'Home') }
      let!(:points) do
        [
          create(:point, user:, lonlat: 'POINT(0 0)', timestamp: 1.hour.ago),
          create(:point, user:, lonlat: 'POINT(0.00001 0.00001)', timestamp: 50.minutes.ago),
          create(:point, user:, lonlat: 'POINT(0.00002 0.00002)', timestamp: 40.minutes.ago)
        ]
      end

      it 'associates the visit with the area' do
        visit = detector.call.first
        expect(visit.area).to eq(area)
        expect(visit.name).to eq('Home')
      end

      context 'with geodata present' do
        let(:geodata) do
          {
            'features' => [
              {
                'properties' => {
                  'type' => 'shop',
                  'name' => 'Coffee Shop',
                  'street' => 'Main Street'
                }
              }
            ]
          }
        end

        let!(:points) do
          [
            create(:point, user:, lonlat: 'POINT(0 0)', timestamp: 1.hour.ago,
                  geodata: geodata),
            create(:point, user:, lonlat: 'POINT(0.00001 0.00001)', timestamp: 50.minutes.ago,
                  geodata: geodata),
            create(:point, user:, lonlat: 'POINT(0.00002 0.00002)', timestamp: 40.minutes.ago,
                  geodata: geodata)
          ]
        end

        it 'prefers area name over geodata' do
          visit = detector.call.first
          expect(visit.name).to eq('Home')
        end
      end
    end

    context 'with points too far apart' do
      let!(:points) do
        [
          create(:point, user:, lonlat: 'POINT(0 0)', timestamp: 1.hour.ago),
          create(:point, user:, lonlat: 'POINT(1 1)', timestamp: 50.minutes.ago), # Far away
          create(:point, user:, lonlat: 'POINT(0.00002 0.00002)', timestamp: 40.minutes.ago)
        ]
      end

      it 'creates separate visits' do
        expect { detector.call }.to change(Visit, :count).by(2)
      end
    end

    context 'with points too far apart in time' do
      let!(:points) do
        [
          create(:point, user:, lonlat: 'POINT(0 0)', timestamp: 2.hours.ago),
          create(:point, user:, lonlat: 'POINT(0.00001 0.00001)', timestamp: 1.hour.ago),
          create(:point, user:, lonlat: 'POINT(0.00002 0.00002)', timestamp: 5.minutes.ago)
        ]
      end

      it 'creates separate visits' do
        expect { detector.call }.to change(Visit, :count).by(2)
      end
    end

    context 'with an existing place' do
      let!(:place) { create(:place, latitude: 0, longitude: 0, name: 'Coffee Shop') }
      let!(:points) do
        [
          create(:point, user:, lonlat: 'POINT(0 0)', timestamp: 1.hour.ago),
          create(:point, user:, lonlat: 'POINT(0.00001 0.00001)', timestamp: 50.minutes.ago),
          create(:point, user:, lonlat: 'POINT(0.00002 0.00002)', timestamp: 40.minutes.ago)
        ]
      end

      it 'associates the visit with the place' do
        visit = detector.call.first
        expect(visit.place).to eq(place)
        expect(visit.name).to eq('Coffee Shop')
      end

      context 'with different geodata' do
        let(:geodata) do
          {
            'features' => [
              {
                'properties' => {
                  'type' => 'restaurant',
                  'name' => 'Burger Place',
                  'street' => 'Main Street'
                }
              }
            ]
          }
        end

        let!(:points) do
          [
            create(:point, user:, lonlat: 'POINT(0 0)', timestamp: 1.hour.ago,
                  geodata: geodata),
            create(:point, user:, lonlat: 'POINT(0.00001 0.00001)', timestamp: 50.minutes.ago,
                  geodata: geodata),
            create(:point, user:, lonlat: 'POINT(0.00002 0.00002)', timestamp: 40.minutes.ago,
                  geodata: geodata)
          ]
        end

        it 'prefers existing place name over geodata' do
          visit = detector.call.first
          expect(visit.place).to eq(place)
          expect(visit.name).to eq('Coffee Shop')
        end
      end
    end
  end
end
